--[[

Example usage:
    medevac
    medevac.buddy=yes
    medevac.freq=30.volume=200
    medevac.delay=20
    medevac.smoke=red


    1. units to count
    2. unit at point of interest
    3. radius of search
    4. shape of search area ( sphere | cylinder )

--]]


medevac = {}

medevac.casualtyName   = "casualty"
medevac.debug          = true
medevac.delimiter      = ","
medevac.messageIdent   = "mvac"
medevac.numGroups      = 16
medevac.spawner        = {}
medevac.unitIndex      = 1
medevac.casualties     = {}
medevac.hospitals      = {}


iotr = {}


iotr.getMessageParameters = function( message, delimiter, defaults )

    --  Set empty defaults if none set
    if ( defaults == nil ) then
        defaults = {}
    end

    --  Parse the message
    local details = string.gmatch( message, "(%w+)=(%w+)" )

    --  Table for the returned information
    local output = {}
    local useOutput = false

    --  Loop and store, e.g. ["freq"]=30, ["volume"]=20
    for key, value in details do
        output[ key ] = value
        useOutput = true
    end

    --  Return defaults if there are no params specified
    if ( useOutput ) then
        
        return output

    else

        return defaults

    end

end

iotr.logger = mist.Logger:new( "IOTR", "info" )

iotr.notify = function( message, ident, timeout )

    --  Set empty ident if not set
    if ( ident == nil ) then
        ident = ""
    else
        ident = "[" .. ident .. "] "
    end

    --  Set timeout if not set
    if ( timeout == nil ) then
        timeout = 3
    end

    trigger.action.outText( ident .. message, timeout )

end

iotr.isIdentTriggeredByMessage = function( ident, message, delimiter )

    if ( delimiter == nil ) then
        delimiter = ","
    end

    if ( ( ident == message ) or ( message:startsWith( ident .. delimiter ) ) ) then
        return true
    end

    return false

end

function string.startsWith( String, Start )
    return string.sub( String, 1, string.len( Start ) ) == Start
end


function table.filter( tbl, callback, reindex )
    local filteredTable = {}
    
    if reindex == nil then
        reindex = false
    end

    for k, v in pairs( tbl ) do
        if callback( k, v ) then
            if reindex == true then
                table.insert( filteredTable, v )
            else
                filteredTable[ k ] = v
            end
        end
    end

    return filteredTable
end


function table.length( tbl )
    local num = 0

    for k, v in pairs( tbl ) do
        num = num + 1
    end

    return num
end



----------------------------------------------------------------------------------
--  Medevac
----------------------------------------------------------------------------------



--  Menu function to collect the casualties
medevac.collectCasualties = function( args )

    local helo = Group.getByName( args._groupName ):getUnit( 1 )

    if ( helo:inAir() ) then
        medevac.notify( "You need to be stationary on the ground", 10 )
        return
    end

    --  Get the nearby casualties
    local nearbyCasualties = medevac.getCasualtiesNearMedevac( medevac.casualties, args._groupName, 50 )

    --  Exit if there are no casualties
    if ( #nearbyCasualties == 0 ) then
        medevac.notify( "No casualties in range.", 10 )
        return
    end

    --  Loop casualties
    for i, casualty in pairs( nearbyCasualties ) do

        casualty.casualty.status            = "onboard"
        casualty.casualty.medevacGroupName  = args._groupName
        
        medevac.notify( casualty.casualty.name .. " is now onboard" )

        --  Destroy (remove) the casualty
        Group.destroy( Group.getByName( casualty.casualty.group ) )

    end

end



--  Menu function to deliver
medevac.deliverCasualties = function( args )

    local helo = Group.getByName( args._groupName ):getUnit( 1 )

    if ( helo:inAir() ) then
        medevac.notify( "You need to be stationary on the ground", 10 )
        return
    end


    --  Ensure the helo has a casualty
    local onboardCasualties = table.filter( medevac.casualties, function( key, value ) 
        return ( value.casualty.medevacGroupName == args._groupName and value.casualty.status == "onboard" )
    end )

    if ( table.length( onboardCasualties ) == 0 ) then
        medevac.notify( "You have no casualties on board.", 10 )
        return
    end

    --  Get the nearby hospitals
    local nearbyHospitals = medevac.getHospitalsNearMedevac( medevac.hospitals, args._groupName, 100 )

    --  Exit if there are no hospitals
    if ( #nearbyHospitals == 0 ) then

        medevac.notify( "No hospitals in range.", 10 )
        return

    else
        
        for i, c in pairs( onboardCasualties ) do
                
            medevac.casualties[i].casualty.status   = "rescued"
            medevac.casualties[i].hospital          = nearbyHospitals[ 1 ].name

            medevac.notify( "You've rescued " .. c.casualty.group .. ".  Well done!", 10 )

        end

    end

end


function medevac.eventHandler( event )

    --  event#26 is the message description update (not the putting of the circle)
    if ( 26 == event.id ) then

        --  Asking for help?
        if ( event.text == "medevac.help" ) then
            medevac.printHelp()
            return
        end

        --  Read the message
        local config = medevac.parseMessage( event )

    end

end



function medevac.getCasualtiesNearMedevac ( casualties, medevacGroupName, range )

    if range == nil then
        range = 100
    end

    local casualtiesInRange = {}

    --  Abort if no casualties registered, for pace (TODO: radio option could be disabled?)
    if #casualties == 0 then
        return casualtiesInRange
    end

    --  Get the helo position
    local heloPos = Group.getByName( medevacGroupName ):getUnit( 1 ):getPosition().p       --  Vec3

    local distance

    casualties = table.filter( casualties, function( key, value )
        return value.casualty.status == "waiting"
    end )

    --  Loop casualties
    for i, casualty in pairs( casualties ) do

        --  Work out the position of the casualty
        local casualtyPos = Group.getByName( casualty.casualty.group ):getUnit( 1 ):getPosition().p

        --  Calculate the distance between helo and casualty
        distance = mist.utils.get3DDist( heloPos, casualtyPos )

        --  If in pick-up range then add to the in-range list
        if ( distance <= range ) then
            table.insert( casualtiesInRange, casualty )
        end

    end

    return casualtiesInRange

end


function medevac.getHospitalsNearMedevac ( hospitals, medevacGroupName, range )

    if range == nil then
        range = 250
    end

    local hospitalsInRange = {}

    --  Abort if no hospitals registered, for pace (TODO: radio option could be disabled?)
    if #hospitals == 0 then
        return hospitalsInRange
    end

    --  Get the helo position
    local heloPos = Group.getByName( medevacGroupName ):getUnit( 1 ):getPosition().p       --  Vec3

    local distance

    --  Loop hospitals
    for i, hospital in pairs( hospitals ) do

        --  Work out the position of the hospital
        local hospitalPos = StaticObject.getByName( hospital.name ):getPosition().p

        --  Calculate the distance between helo and hospital
        distance = mist.utils.get3DDist( heloPos, hospitalPos )

        --  If in pick-up range then add to the in-range list
        if ( distance <= range ) then
            table.insert( hospitalsInRange, hospital )
        end

    end

    return hospitalsInRange


end


function medevac.listCasualties( args )

    local casualtiesToBeRescued = table.filter( medevac.casualties, function( key, value )
        return value.casualty.status == "waiting"
    end )

    local output = ""
    local groupName

    for i, casualty in pairs( casualtiesToBeRescued ) do

        groupName = casualty.casualty.group
        output    = output .. "\n#" .. i .. ": " .. groupName

        output = output .. " - " .. mist.getBRString({
            units   = mist.makeUnitTable({ "[g]" .. groupName } ),
            ref     = mist.utils.makeVec3GL( coalition.getMainRefPoint( coalition.side.BLUE ) ),
            alt     = false,
            metric  = false
        })

        if ( casualty.radio ) then
            output = output .. " - " .. casualty.radio.freq .. "AM"
        end

        if ( casualty.smoke ) then
            output = output .. " - " .. casualty.smoke.colour .. " smoke"
        end

    end

    if output == "" then
        medevac.notify( "No casualties are waiting for rescue." )
    else
        medevac.notify( "Casualties:" .. output )
    end

end


function medevac.listHospitals( args )

    local text = ""
    local distance, hospitalPos

    local heloPos = Group.getByName( args._groupName ):getUnit( 1 ):getPosition().p       --  Vec3

    for i, h in ipairs( medevac.hospitals ) do

        text = text .. "\n" .. h.name

        hospitalPos = StaticObject.getByName( h.name ):getPosition().p

        --  Calculate the distance between helo and hospital
        distance = mist.utils.get3DDist( heloPos, hospitalPos )

        text = text .. " - " .. ( math.ceil( mist.utils.metersToNM( distance * 10 ) ) / 10 ) .. "nm"

        if ( h.radio ) then
            text = text .. " - " .. h.radio.freq .. "mhz"       
        end

    end

    medevac.notify( "Hospitals:" .. text, 10 )

end


function medevac.log( msg )

    iotr.logger:info( msg )

end


function medevac.notify( msg, timeout )

    if ( medevac.debug ) then

        iotr.notify( msg, medevac.messageIdent, timeout )

    end

end


function medevac.parseMessage( event )

    --  Force lowercase just... in...  case...
    local message   = event.text:lower();
    local location  = mist.utils.makeVec3GL( event.pos )

    --  Check we're working on medevac
    local isMedevac     = iotr.isIdentTriggeredByMessage( medevac.messageIdent, message, medevac.delimiter )
    local isHospital    = iotr.isIdentTriggeredByMessage( medevac.messageIdent .. "-hospital", message )
    local defaults      = {}
    local config        = {}

    if ( isMedevac ) then

        --  Table to store details
        --  defaults[ "radio" ] = "yes"

        config = iotr.getMessageParameters( message, medevac.delimiter, defaults )

        if config.delay and tonumber( config.delay ) > 0 then

            mist.scheduleFunction(
                function( location, config )
                    medevac.spawner.spawnCasualty( location, config )
                end,
                {
                    location,
                    config
                },
                timer.getTime() + tonumber( config.delay )
            )

        else

            medevac.spawner.spawnCasualty( location, config )

        end
        

    elseif ( isHospital ) then

        config = iotr.getMessageParameters( message, medevac.delimiter, defaults )

        medevac.spawner.spawnHospital( location, config )
    
    else
        
        return false

    end

end


function medevac.printHelp()

    local content = "Parameters:"
        -- .. "\n- buddy=(int) - makes "
        .. "\n- Radio beacon"
        .. "\n     a) *radio=yes (default options)"
        .. "\n     b1) freq=(int)"
        .. "\n     b2) volume=(int, 1-200, optional, default 50)"
        .. "\n- Smoke"
        .. "\n     a) *smoke=yes (default blue)"
        .. "\n     b) smoke=[blue|green|orange|red|white]"
        .. "\n"
        .. "\n-- Examples"--
        .. "\n" .. medevac.messageIdent .. " (no assistance)"
        .. "\n" .. medevac.messageIdent .. medevac.delimiter .. "freq=220" .. medevac.delimiter .. "smoke=orange"
        .. "\n" .. medevac.messageIdent .. medevac.delimiter .. "freq=220.volume=20" .. medevac.delimiter .. "smoke=orange"
        .. "\n" .. medevac.messageIdent .. medevac.delimiter .. "smoke=white"
        .. "\n\n** Remember to spawn a rescue hospital using \"" .. medevac.messageIdent .. "-hospital\" **"

    medevac.notify( content, 30 )

end



medevac.setupF10Radio = function()

    local unitGroups = table.filter( mist.DBs.MEgroupsByName, function( key, value )
        return value.category == "helicopter" or value.category == "plane"
    end )

    local args, casualtiesMenu, hospitalsMenu, isHelo, medevacMenu

    for i, unitGroup in pairs( unitGroups ) do

        isHelo = ( unitGroup.category == "helicopter" )

        args = {
            [ "_groupId" ]      = unitGroup.groupId,
            [ "_groupName" ]    = unitGroup.groupName
        }

        medevacMenu     = missionCommands.addSubMenuForGroup( unitGroup.groupId, "Medevac", nil )

        --  Casualties sub-menu
        casualtiesMenu  = missionCommands.addSubMenuForGroup( unitGroup.groupId, "Casualties", medevacMenu )

        missionCommands.addCommandForGroup( unitGroup.groupId, "List casualties", casualtiesMenu, medevac.listCasualties, args )
        
        if ( isHelo ) then
            missionCommands.addCommandForGroup( unitGroup.groupId, "Airlift nearby casualties", casualtiesMenu, medevac.collectCasualties, args )
            missionCommands.addCommandForGroup( unitGroup.groupId, "Deliver casualty", casualtiesMenu, medevac.deliverCasualties, args )
        end

        --  Hospitals sub-menu
        hospitalsMenu   = missionCommands.addSubMenuForGroup( unitGroup.groupId, "Hospitals", medevacMenu )
        missionCommands.addCommandForGroup( unitGroup.groupId, "List hospitals", hospitalsMenu, medevac.listHospitals, args )

        --  Help
        missionCommands.addCommandForGroup( unitGroup.groupId, "Medevac help", medevacMenu, medevac.printHelp )

    end

    
end


------------------------------------------------------------------
--  Spawner
------------------------------------------------------------------


--  Additional features
function medevac.spawner.spawnAdditionalFeatures( location, object, config )

    --  Radio

    if ( config[ "radio" ] == "yes" or config[ "freq" ] ~= nil ) then

        if ( config[ "freq" ] == nil ) then
            config[ "freq" ] = tostring( object.defaultFreq )
        end
        
        object.radio = medevac.spawner.transmitRadioSignal( location, config[ "freq" ], config[ "volume" ] )

    end


    --  Smoke

    if ( config[ "smoke" ] ) then
        
        object.smoke = medevac.spawner.spawnSmoke( location, config[ "smoke" ] )

    end

    return object

end


--  Casualty

function medevac.spawner.spawnCasualty( location, config )

    local casualtyName = medevac.casualtyName .. tostring( medevac.unitIndex )

    local unit = mist.dynAdd({
        category    = "vehicle",
        country     = "USA",
        group       = "casualty" .. tostring( medevac.unitIndex ),
        hidden      = true,
        name        = "casualty" .. tostring( medevac.unitIndex ),
        units       = {
            [ 1 ] = {

                [ "heading" ]       = 6.2 + 11,
                [ "playerCanDrive"] = false,

                type            = "Soldier M4",
                x               = location.x + 0.65,
                y               = location.z - 0.57

            },
        },
        visible      = false
    })

    unit.status = "waiting"

    unit.defaultFreq = 200 + medevac.unitIndex  -- start at 201

    unit = medevac.spawner.spawnAdditionalFeatures( location, unit, config )

    --  Add casualty to casualty list
    medevac.casualties[ medevac.unitIndex ] = {}
    medevac.casualties[ medevac.unitIndex ].casualty = unit
    medevac.unitIndex = medevac.unitIndex + 1

    medevac.notify( "Casualty " .. casualtyName .. " reported" )

    return unit


end


--  Hospital

function medevac.spawner.spawnHospital( location, config )

    local hospitalName = "hospital-" .. tostring( #medevac.hospitals )

    local hospital = mist.dynAddStatic({
        category    = "Structures",
        country     = "USA",
        dead        = false,
        heading     = 6.2,
        name        = hospitalName,
        type        = "VPC-NATO-HOUSE 2",
        x           = location.x,
        y           = location.z
    })

    hospital.defaultFreq = 400 + #medevac.hospitals + 1  -- start at 401

    hospital = medevac.spawner.spawnAdditionalFeatures( location, hospital, config )

    table.insert( medevac.hospitals, hospital )

    medevac.notify( "Hospital " .. hospitalName .. " spawned" )

    return hospital

end


--  Smoke

function medevac.spawner.spawnSmoke( location, colour )

    local smokeLocation = mist.utils.makeVec3GL( mist.getRandPointInCircle( location, 40, 20 ) )

    local colourMap = {}
    colourMap[ "blue" ]     = trigger.smokeColor.Blue
    colourMap[ "green" ]    = trigger.smokeColor.Green
    colourMap[ "orange" ]   = trigger.smokeColor.Orange
    colourMap[ "red" ]      = trigger.smokeColor.Red
    colourMap[ "white" ]    = trigger.smokeColor.White

    if ( colour == nil or colourMap[ colour ] == nil ) then
        colour = "blue"
    end

    local smoke = {
        colour = colour
    }
    
    trigger.action.smoke( smokeLocation, colourMap[ colour ] )

    medevac.notify( colour .. " smoke spawned" )

    return smoke

end



--  Transmit Radio

function medevac.spawner.transmitRadioSignal( location, freq, volume )

    local freq_mhz = tonumber( freq ) * ( 10 ^ ( 6 - freq:len() ) );

    if ( volume == nil ) then
        volume = 100;
    end

    medevac.log( "freq_mhz :: " .. freq_mhz )

    local transmission = {
        [ "beacon" ]    = trigger.action.radioTransmission( "l10n/DEFAULT/elt1.wav", location, 0, true, freq_mhz, volume ),
        [ "freq" ]      = freq
    }

    medevac.notify( "Radio transmission broadcast on " .. transmission.freq .. "khz" )

    return transmission

end


----------------------------------------------------------------------
--  Boot code
----------------------------------------------------------------------

mist.addEventHandler( medevac.eventHandler )
medevac.setupF10Radio()