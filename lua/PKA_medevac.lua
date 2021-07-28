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
medevac.messageIdent   = "medevac"
medevac.numGroups      = 16
medevac.spawner        = {}
medevac.unitIndex      = 1
medevac.casualties     = {}
medevac.hospitals      = {}


iotr = {}


iotr.addCommandForSequentialGroup = function( groupNameStem, numGroups, menuText, paths, func, arguments )

    local returnPaths = {}
    local unitGroup
    local unitMenuPath
    
    if ( arguments == nil ) then
        arguments = {} 
    end

    for i = 1,numGroups,1 do

        groupName  = groupNameStem .. tostring( i )
        unitGroup  = Group.getByName( groupName )

        if unitGroup then
            local groupId = unitGroup:getID()

            if ( type( arguments ) == "table" ) then
                arguments[ "_groupId" ]     = groupId
                arguments[ "_groupName" ]   = groupName
            end

            if ( type( paths ) == "table" and paths[ i ] ) then
                unitMenuPath = paths[ i ]
            else
                unitMenuPath = nil
            end

            returnPaths[ i ] = {
                [ "path" ]      = missionCommands.addCommandForGroup( groupId, menuText, unitMenuPath, func, arguments ),
                [ "arguments" ] = arguments
            }

         end
    end

    return returnPaths

end


iotr.addMenuForSequentialGroup = function( groupNameStem, numGroups, menuText, path )

    local returnPaths = {}
    local unitGroup

    for i = 1,numGroups,1 do

        local groupName  = groupNameStem .. tostring( i )
        unitGroup  = Group.getByName( groupName )

        if unitGroup then

            local groupId = unitGroup:getID()
            returnPaths[ i ] = missionCommands.addSubMenuForGroup( groupId, menuText, path )

         end
    end

    return returnPaths

end


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

    medevac.log( "\n\n\n@getMessageParameters --> " .. message .. mist.utils.tableShow( output ) )

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
        delimiter = "."
    end

    if ( ( ident == message ) or ( message:find( ident .. delimiter ) == 1 ) ) then
        return true
    end

end

function string.startsWith( String, Start )
    return string.sub( String, 1, string.len( Start ) ) == Start
end


function table.filter( tbl, callback )
    local filteredTable = {}

    for k, v in pairs( tbl ) do
        if callback( k, v ) then
            filteredTable[ k ] = v
        end
    end

    return filteredTable
end



----------------------------------------------------------------------------------
--  Medevac
----------------------------------------------------------------------------------


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


function medevac.log( msg )

    iotr.logger:info( msg )

end


function medevac.notify( msg, timeout )

    if ( medevac.debug ) then

        iotr.notify( msg, medevac.messageIdent, timeout )

    end

end


function medevac.parseMessage ( event )

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
        defaults[ "radio" ] = "yes"

        config = iotr.getMessageParameters( message, medevac.delimiter, defaults )
        
        --  Start spawner
        medevac.spawner.spawnCasualty( location, config )

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
        .. "\nmedevac (same as medevac.radio=yes)"
        .. "\nmedevac" .. medevac.separator .. "freq=3325" .. medevac.separator .. "smoke=orange"
        .. "\nmedevac" .. medevac.separator .. "freq=375.volume=20" .. medevac.separator .. "smoke=orange"
        .. "\nmedevac" .. medevac.separator .. "smoke=white"
        .. "\n\n** Remember to spawn a rescue hospital using \"medevac-hospital\" **"

    medevac.notify( content, 30 )

end


------------------------------------------------------------------
--  Spawner
------------------------------------------------------------------


--  Additional features
function medevac.spawner.spawnAdditionalFeatures( location, object, config )

    
    medevac.log( "\n\n\n@spawnAdditionalFeatures --> " .. mist.utils.tableShow( config ) )

    --  Radio

    if ( config[ "radio" ] == "yes" or config[ "freq" ] ~= nil ) then

        if ( config[ "freq" ] == nil ) then
            config[ "freq" ] = tostring( 30 + ( medevac.unitIndex - 1 ) )
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
        name        = "casualty" .. tostring( medevac.unitIndex ),
        units       = {
            [ 1 ] = {

                [ "heading" ]       = 6.2 + 11,
                [ "playerCanDrive"] = true,

                type            = "Soldier M4",
                x               = location.x + 0.65,
                y               = location.z - 0.57

            },
        }
    })

    unit.status = "waiting"

    medevac.log( "\n\n\ncasualty@spawnAdditionalFeatures --> " .. mist.utils.tableShow( config ) )

    unit = medevac.spawner.spawnAdditionalFeatures( location, unit, config )

    --  Add casualty to casualty list
    medevac.casualties[ medevac.unitIndex ] = {}
    medevac.casualties[ medevac.unitIndex ].casualty = unit
    medevac.unitIndex = medevac.unitIndex + 1

    medevac.notify( "Casualty " .. casualtyName .. " spawned" )

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

    medevac.log( "\n\n\nhospital@spawnAdditionalFeatures --> " .. mist.utils.tableShow( config ) )

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

    local smoke = trigger.action.smoke( smokeLocation, colourMap[ colour ] )

    medevac.notify( colour .. " smoke spawned" )

    return smoke

end



--  Transmit Radio

function medevac.spawner.transmitRadioSignal( location, freq, volume )

    local freq_mhz = tonumber( freq ) * ( 10 ^ ( 8 - freq:len() ) );

    if ( volume == nil ) then
        volume = 100;
    end

    local transmission = trigger.action.radioTransmission( "l10n/DEFAULT/elt1.wav", location, 1, true, freq_mhz, volume )

    medevac.notify( "Radio transmission broadcast on " .. freq .. "FM" )

    return transmission

end


----------------------------------------------------------------------
--  Main handler
----------------------------------------------------------------------

mist.addEventHandler( medevac.eventHandler )



medevac.getHospitalsNearMedevac = function( hospitals, medevacGroupName, range )

    if range == nil then
        range = 250
    end

    local hospitalsInRange = {}
    medevac.log( "\n\n\n@all hospitals --> " .. mist.utils.tableShow( hospitals ) )

    --  Abort if no hospitals registered, for pace (TODO: radio option could be disabled?)
    if #hospitals == 0 then
        medevac.log( "\n\n\nNo hospitalsInRange" )
        return hospitalsInRange
    end

    --  Get the helo position
    local heloPos = Group.getByName( medevacGroupName ):getUnit( 1 ):getPosition().p       --  Vec3

    local distance

    --  Loop hospitals
    for i, hospital in pairs( hospitals ) do

        medevac.log( "\n\n\n@hospital --> " .. mist.utils.tableShow( hospital ) )

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



medevac.getCasualtiesNearMedevac = function( casualties, medevacGroupName, range )

    if range == nil then
        range = 100
    end

    local casualtiesInRange = {}
    medevac.log( "\n\n\n@all casualties --> " .. mist.utils.tableShow( casualties ) )

    --  Abort if no casualties registered, for pace (TODO: radio option could be disabled?)
    if #casualties == 0 then
        medevac.log( "\n\n\nNo casualtiesInRange" )
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

        medevac.log( "\n\n\n@casualty --> " .. mist.utils.tableShow( casualty ) )

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


--  Menu function to collect the casualties
medevac.collectCasualties = function( args )

    --  Get the nearby casualties
    local nearbyCasualties = medevac.getCasualtiesNearMedevac( medevac.casualties, args._groupName )

    --  Exit if there are no casualties
    if ( #nearbyCasualties == 0 ) then
        medevac.notify( "No casualties in range.", 10 )
        return
    end

    --  Loop casualties
    for i, casualty in pairs( nearbyCasualties ) do

        medevac.log( "\n\n\n@casualty" .. i .. " casualty --> " .. casualty.casualty.name )

        casualty.casualty.status            = "onboard"
        casualty.casualty.medevacGroupName  = args._groupName

        --  Destroy (remove) the casualty
        Group.destroy( Group.getByName( casualty.casualty.group ) )

    end

end


--  Menu function to deliver
medevac.deliverCasualties = function( args )

    --  Ensure the helo has a casualty
    local onboardCasualties = table.filter( medevac.casualties, function( key, value ) 
        return ( value.casualty.medevacGroupName == args._groupName and value.casualty.status == "onboard" )
    end )

    if ( #onboardCasualties == 0 ) then
        medevac.notify( "You have no casualties on board.", 10 )
        return
    end

    --  Get the nearby hospitals
    local nearbyHospitals = medevac.getHospitalsNearMedevac( medevac.hospitals, args._groupName )

    --  Exit if there are no hospitals
    if ( #nearbyHospitals == 0 ) then

        medevac.notify( "No hospitals in range.", 10 )
        return

    else

        medevac.log( "\n\n\n@cazzies --> " .. mist.utils.tableShow( medevac.casualties ) )
        
        for i, c in pairs( onboardCasualties ) do
                
            medevac.casualties[i].casualty.status   = "rescued"
            medevac.casualties[i].hospital          = nearbyHospitals[ 1 ].name

            medevac.notify( "You've rescued " .. c.casualty.group .. ".  Well done!", 10 )

        end

    end

end



--  Add main "Medevac" menu to F10
local menuOptions = iotr.addMenuForSequentialGroup( "medevac-", medevac.numGroups, "Medevac" )

--  Add options
iotr.addCommandForSequentialGroup( "medevac-", #menuOptions, "Airlift nearby casualties", menuOptions, medevac.collectCasualties )
iotr.addCommandForSequentialGroup( "medevac-", #menuOptions, "Deliver casualty", menuOptions, medevac.deliverCasualties )
