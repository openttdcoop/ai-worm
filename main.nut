/**
 * WormAI: An OpenTTD AI
 * First version based on WrightAI
 * 
 * @file main.nut Main class and loop of our AI for OpenTTD.
 * License: GNU GPL - version 2 (see license.txt)
 * Author: Wormnest (Jacob Boerema)
 * Copyright: Jacob Boerema, 2013-2016.
 *
 */ 

// Get the latest libversions
// This is autogenerated by a script to always have up to date version numbers
require("libversions.nut");

// Import SuperLib
import("util.superlib", "SuperLib", SUPERLIB_VERSION);

/** @name SuperLib imports */
/// @{
Result <- SuperLib.Result;
Log <- SuperLib.Log;
Helper <- SuperLib.Helper;
Data <- SuperLib.DataStore;
ScoreList <- SuperLib.ScoreList;
Money <- SuperLib.Money;

Tile <- SuperLib.Tile;
Direction <- SuperLib.Direction;

Engine <- SuperLib.Engine;
Vehicle <- SuperLib.Vehicle;

Station <- SuperLib.Station;
Airport <- SuperLib.Airport;
Industry <- SuperLib.Industry;
Town <- SuperLib.Town;

Order <- SuperLib.Order;
OrderList <- SuperLib.OrderList;

Road <- SuperLib.Road;
RoadBuilder <- SuperLib.RoadBuilder;
/// @}

// Import List library
import("AILib.List", "ExtendedList", AILIBLIST_VERSION);

// Get our required classes.
require("money.nut");
require("strings.nut");
require("tiles.nut");
require("airmanager.nut");

/* Default delays */
const SLEEPING_TIME = 100;						///< Default time to sleep between loops of our AI (NB: should be a multiple of 100).
const DEFAULT_DELAY_BUILD_AIRPORT = 500; 		///< Default delay before building a new airport route.

/// @{
/** @name ERROR CODE constants */
const ALL_OK = 0;
const ERROR_FIND_AIRPORT1	= -1;				///< There was an error finding a spot for airport 1.
const ERROR_FIND_AIRPORT2	= -2;				///< There was an error finding a spot for airport 2.
const ERROR_BUILD_AIRPORT1	= -3;				///< There was an error building airport 1.
const ERROR_BUILD_AIRPORT2	= -4;				///< There was an error building airport 2.
const ERROR_FIND_AIRPORT_ACCEPTANCE = -5;		///< We couldn't find a suitable airport but we lowered our acceptance rate limit so we can try again.
const ERROR_FIND_AIRPORT_FINAL = -6;			///< We couldn't find a suitable airport and we are at the minimum acceptable acceptance limit.
const ERROR_NO_SUITABLE_AIRPORT = -7;			///< There is no suitable airport type available.
const ERROR_MAX_AIRCRAFT = -10;					///< We have reached the maximum allowed number of aircraft.
const ERROR_MAX_AIRPORTS = -11;					///< We have reached the maximum number of airports.
const ERROR_NOT_ENOUGH_MONEY = -20;				///< We don't have enough money.
const ERROR_BUILD_AIRCRAFT = -30;				///< General error trying to build an aircraft.
const ERROR_BUILD_AIRCRAFT_INVALID = -31;		///< No suitable aircraft found when trying to build an aircraft.
/// @}

/**
 * Define the main class of our AI WormAI.
 */
class WormAI extends AIController {
	/* Declare the variables here. */
	name = null;								///< The name that we will give our AI
	air_manager = null;							///< The Air Manager class

	ai_speed_factor = 1;						///< speed factor for our ai actions (1=fast..3=slow)
	delay_build_airport_route = 0;
	
	use_air = false;							///< Whether we can use aircraft or not
	use_trains = false;							///< Whether we can use trains or not

	loaded_from_save = false;
	aircraft_disabled_shown = 0;		///< Has the aircraft disabled in game settings message been shown (1) or not (0).
	aircraft_max0_shown = 0;			///< Has the max aircraft is 0 in game settings message been shown.
	trains_disabled_shown = 0;			///< Has the trains disabled in game settings message been shown (1) or not (0).
	trains_max0_shown = 0;				///< Has the max trains is 0 in game settings message been shown.

	/** Create an instance of WormAI. */
	constructor()
	{
		/* Initialize the class variables here (or later when possible). */
		this.loaded_from_save = false;
		/* Instantiate our AirManager. */
		this.air_manager = WormAirManager();
		
		this.aircraft_disabled_shown = 0;
		this.aircraft_max0_shown = 0;
		// Delays: we don't set them here but in start because we need to check the selected
		// speed set in game settings

	}

    /// @{
	/** @name Implementation of base class functions */
	/**
	 * Start the main loop of WormAI.
	 */
	function Start();
	/**
	 * Save all data that WormAI uses.
	 * @return The data to be saved.
	 */
	function Save();
	/**
	 * Load previously saved information.
	 * @param version Which version of our AI saved the information.
	 * @param data The data that was saved.
	 */
	function Load(version, data);
	/// @}

	/** @name Initialization functions */
    /// @{
	/**
	 * InitSettings initializes a number of required variables based on the game settings of our AI.
	 */
	function InitSettings();
	/**
	 * Welcome says hello to the user and prints out the current AI gamesettings.
	 */
	function Welcome();
	/**
	 * Checks if we can build an aircraft and if not outputs a string with the reason.
	 * @return true if we can build an aircraft, otherwise false.
	 */
	function CanBuildAircraft();
	/**
	 * Checks if we can build trains and if not outputs a string with the reason.
	 * @return true if we can build trains, otherwise false.
	 */
	function CanBuildTrains();
	/// @}

};

/**
 * InitSettings initializes a number of required variables based on the game settings of our AI.
 */
function WormAI::InitSettings()
{
	local ai_speed = GetSetting("ai_speed");
	switch (ai_speed) {
		case 1: {this.ai_speed_factor = 3;} break;
		case 3: {this.ai_speed_factor = 1;} break;
		default: {this.ai_speed_factor = 2;} break;
	}
	
	this.delay_build_airport_route = DEFAULT_DELAY_BUILD_AIRPORT * this.ai_speed_factor;
	
	/* Since autorenew can change the vehicle id it may cause trouble to have it turned on,
	 * therefore we turn it off and will renew manually in the future. */
	AICompany.SetAutoRenewStatus(false); 
}

/**
 * Welcome says hello to the user and prints out the current AI gamesettings.
 */
function WormAI::Welcome()
{
	/* Say hello to the user */
	AILog.Info("Welcome to WormAI.");
	AILog.Info("These are our current AI settings:");
	AILog.Info("- Use planes: " + GetSetting("use_planes"));
	AILog.Info("- Use trains: " + GetSetting("use_trains"));
	AILog.Info("- AI speed: " + GetSetting("ai_speed"));
	AILog.Info("- Minimum Town Size: " + GetSetting("min_town_size"));
	AILog.Info("- Minimum Airport Distance: " + GetSetting("min_airport_distance"));
	AILog.Info("- Maximum Airport Distance: " + GetSetting("max_airport_distance"));
	AILog.Info("----------------------------------");
}

/**
 * Checks if we can build an aircraft and if not outputs a string with the reason.
 * @return true if we can build an aircraft, otherwise false.
 */
function WormAI::CanBuildAircraft()
{
	/* Need to check if we can build aircraft and how many. Since this can change we do it inside the loop. */
	if (AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_AIR)) {
		if (this.aircraft_disabled_shown == 0) {
			AILog.Warning("Using aircraft is disabled in your game settings.")
			AILog.Warning("No air routes will be built until you change this setting.")
			this.aircraft_disabled_shown = 1;
		}
	}
	else if (Vehicle.IsVehicleTypeDisabledByAISettings(AIVehicle.VT_AIR)) {
		if (this.aircraft_disabled_shown == 0) {
			AILog.Warning("Using aircraft is disabled in this AI's settings.")
			AILog.Warning("No air routes will be built until you change this setting.")
			this.aircraft_disabled_shown = 1;
		}
	}
	else if (Vehicle.GetVehicleLimit(AIVehicle.VT_AIR) == 0) {
		if (this.aircraft_max0_shown == 0) {
			AILog.Warning("Amount of allowed aircraft for AI is set to 0 in your game settings.")
			AILog.Warning("No air routes will be built until you change this setting.")
			this.aircraft_max0_shown = 1;
		}
	}
	else {
		return true;
	}
	return false;
}

/**
 * Checks if we can build trains and if not outputs a string with the reason.
 * @return true if we can build trains, otherwise false.
 */
function CanBuildTrains()
{
	/* Need to check if we can build trains and how many. Since this can change we do it inside the loop. */
	if (AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_RAIL)) {
		if (this.aircraft_disabled_shown == 0) {
			AILog.Warning("Using trains is disabled in your game settings.")
			AILog.Warning("No train routes will be built until you change this setting.")
			this.trains_disabled_shown = 1;
		}
	}
	else if (Vehicle.IsVehicleTypeDisabledByAISettings(AIVehicle.VT_RAIL)) {
		if (this.aircraft_disabled_shown == 0) {
			AILog.Warning("Using trains is disabled in this AI's settings.")
			AILog.Warning("No train routes will be built until you change this setting.")
			this.trains_disabled_shown = 1;
		}
	}
	else if (Vehicle.GetVehicleLimit(AIVehicle.VT_RAIL) == 0) {
		if (this.aircraft_max0_shown == 0) {
			AILog.Warning("Amount of allowed trains is set to 0 in your game settings.")
			AILog.Warning("No train routes will be built until you change this setting.")
			this.trains_max0_shown = 1;
		}
	}
	else {
		return true;
	}
	return false;
}

/**
 * Start the main loop of WormAI.
 */
function WormAI::Start()
{
	if (air_manager.passenger_cargo_id == -1) {
		AILog.Error("WormAI could not find the passenger cargo.");
		return;
	}

	/* Give the AI a name */
	if (!AICompany.SetName("WormAI")) {
		local i = 2;
		while (!AICompany.SetName("WormAI #" + i)) {
			i++;
		}
	}
	this.name = AICompany.GetName(AICompany.COMPANY_SELF);
	
	InitSettings();	// Initialize some AI game settings.
	Welcome();		// Write welcome and AI settings in log.
	
	if (loaded_from_save) {
		air_manager.AfterLoading();
	}

	/* We need our local tickers, as GetTick() will skip ticks */
	local old_ticker = 0;
	local cur_ticker = 0;
	/* The amount of time we may sleep between loops.
	   Warning: don't change this value unless your understand the implications for all the delays! 
	*/
	local sleepingtime = SLEEPING_TIME;
	/* Factor to multiply the build delay with. */
	local build_delay_factor = 1;
	
	local cur_year = 0;
	local new_year = 0;
	local cur_month = 0;
	local new_month = 0;

	/* Let's go on forever */
	while (true) {
		cur_ticker = GetTick();
		/* Check if we can build aircraft or trains. If yes then handle some tasks. */
		/* Since these values can be changed in game we need to re-check them regularly. */
		this.use_air = CanBuildAircraft();
		this.use_trains = CanBuildTrains();
		
		/* Task scheduling. */
		new_year = AIDate.GetYear(AIDate.GetCurrentDate());
		if (cur_year != new_year) { // Use != instead of < since user can cheat and turn back time
			// Handle once a year tasks here.
			AILog.Info(Helper.GetCurrentDateString() + " --- Yearly Tasks ---");
			cur_year = new_year;
			if (this.use_air) {
				/* Evaluate best aircraft: Needs to be done every year to be sure it's done 
				   the first time before we try to build a route. */
				this.air_manager.EvaluateAircraft();
				/* Build a headquarter if it doesn't exist yet and our speed settings is at least medium. */
				if (this.ai_speed_factor < 3) {
					this.air_manager.BuildHQ();
					/* Build statues only in fast, hard mode. */
					if (this.ai_speed_factor < 2) {
						this.air_manager.BuildStatues();
					}
				}
			}
			
			/* Some things we do more or less often depending on this.ai_speed_factor setting */
			if (cur_year % this.ai_speed_factor == 0) {
				/* Nothing for now. */
				}
			
			/* This seems like a good place to show some debugging info in case we turned
			   that setting on. Always once a year. */
			if (GetSetting("debug_show_lists") == 1) {
				/* Debugging info */
				this.air_manager.DebugListTownsUsed();
				//DebugListRouteInfo();
				this.air_manager.DebugListRoutes();
				//DebugListRoute(route_1);
				//DebugListRoute(route_2);
			}
			
			AILog.Info(Helper.GetCurrentDateString() + " --- Yearly Tasks Done ---");
		}
		new_month = AIDate.GetMonth(AIDate.GetCurrentDate());
		if (cur_month != new_month) { // Don't use < here since we need to handle December -> January
			// Handle once a month tasks here.
			AILog.Info(Helper.GetCurrentDateString() + " --- Monthly Tasks ---");
			cur_month = new_month;

			/* Some things we do more or less often depending on this.ai_speed_factor setting */
			if (cur_month % this.ai_speed_factor == 0) {
				if (this.use_air) {
					/* Manage the routes once in a while */
					this.air_manager.ManageAirRoutes();
					this.air_manager.CheckForAirportsNeedingToBeUpgraded();
				}
			}

			if (this.use_air) {
				this.air_manager.ManageVehicleRenewal();
				/* TEST ONCE A MONTH? SELL VEHICLES IN DEPOT */
				this.air_manager.SellVehiclesInDepot();
			}
			
			/* Try to get rid of our loan once in a while */
			AICompany.SetLoanAmount(0);
			
			AILog.Info(Helper.GetCurrentDateString() + " --- Monthly Tasks Done ---");
		}

		/* Once in a while try to build something */
		if (this.use_air) {
			if ((cur_ticker - old_ticker > build_delay_factor * this.delay_build_airport_route) || old_ticker == 0) {
				local ret = this.air_manager.BuildAirportRoute();
				if ((ret == ERROR_FIND_AIRPORT1) || (ret == ERROR_MAX_AIRPORTS) ||
					(ret == ERROR_MAX_AIRCRAFT) && old_ticker != 0) {
					/* No more routes found or we have the max allowed aircraft, delay even more before trying to find an other */
					build_delay_factor = 10;
				}
				else {
					/* Set default delay back in case we had it increased, see above. */
					build_delay_factor = 1;
				}
				old_ticker = cur_ticker;
			}

			/* Check for events once in a while */
			this.air_manager.HandleEvents();
		}

		/* Make sure we do not create infinite loops */
		Sleep(sleepingtime);
	} // END OF OUR MAIN LOOP
}

/**
 * Save all data that WormAI uses.
 * @return The data to be saved.
 */
function WormAI::Save()
 {
   /* Debugging info */
	local MyOps1 = this.GetOpsTillSuspend();
	local MyOps2 = 0;
/* only use for debugging:
    AILog.Warning("Saving data to savegame not implemented yet!");
    AILog.Info("Ops till suspend: " + this.GetOpsTillSuspend());
    AILog.Info("");
*/
    /* Save the data */
    local table = {
		townsused = null,
		route1 = null,
		route2 = null,
	};
	/// @todo This should be moved to a AirManager.SaveData function.
	local t = ExtendedList();
	local r1 = ExtendedList();
	local r2 = ExtendedList();
	t.AddList(this.air_manager.towns_used);
	table.townsused = t.toarray();
	r1.AddList(this.air_manager.route_1);
	table.route1 = r1.toarray();
	r2.AddList(this.air_manager.route_2);
	table.route2 = r2.toarray();
	
    /* Debugging info 
    DebugListTownsUsed();
    DebugListRouteInfo();
*/   
/* only use for debugging:
    AILog.Info("Tick: " + this.GetTick() );
*/
    MyOps2 = this.GetOpsTillSuspend();
	if (MyOps2 < 10000) {
		AILog.Error("SAVE: Using almost all allowed ops: " + MyOps2 );
	}
	else if (MyOps2 < 20000) {
		AILog.Warning("SAVE: Using a high amount of ops: " + MyOps2 );
	}
	else {
		AILog.Info("Saving WormAI game data. Used ops: " + (MyOps1-MyOps2) );
	}
   
    return table;
 }
 
/**
 * Load previously saved information.
 * @param version Which version of our AI saved the information.
 * @param data The data that was saved.
 */
function WormAI::Load(version, data)
 {
   /* Debugging info */
	local MyOps1 = this.GetOpsTillSuspend();
	local MyOps2 = 0;
	AILog.Info("Loading savegame saved by WormAI version " + version);
	/// @todo load data in temp values then later unpack it because
	/// load has limited time available
	/// @todo This should call air_manager.LoadData for air related SaveGame data.
	if ("townsused" in data) {
		local t = ExtendedList();
		t.AddFromArray(data.townsused)
		this.air_manager.towns_used.AddList(t);
	}
	if ("route1" in data) {
		local r = ExtendedList();
		r.AddFromArray(data.route1)
		this.air_manager.route_1.AddList(r);
	}
	if ("route2" in data) {
		local r = ExtendedList();
		r.AddFromArray(data.route2)
		this.air_manager.route_2.AddList(r);
	}
	loaded_from_save = true;

    /* Debugging info */
    MyOps2 = this.GetOpsTillSuspend();
	if (MyOps2 < 10000) {
		AILog.Error("LOAD: Using almost all allowed ops: " + MyOps2 );
	}
	else if (MyOps2 < 20000) {
		AILog.Warning("LOAD: Using a high amount of ops: " + MyOps2 );
	}
	else {
		AILog.Info("Loading WormAI game data. Used ops: " + (MyOps1-MyOps2) );
		//AILog.Info("Loading: ops till suspend: " + MyOps2 + ", ops used in load: " + (MyOps1-MyOps2) );
	}
 }
 