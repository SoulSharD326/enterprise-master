#include <sourcemod>
#include <enterprise>

#define SQL_DATABASE				"enterprise-database"
#define INVALID_TIMESTAMP			-1
#define SCHEDULE_LIMIT				64

#define DEFAULT_SETUP_TIME			90
#define DEFAULT_MINIMUM_PLAYERS		2
#define DEFAULT_MAXIMUM_PLAYERS		32

new Handle:db = INVALID_HANDLE;

new eventTimestamp[SCHEDULE_LIMIT] = {INVALID_TIMESTAMP, ...};
new Event:eventType[SCHEDULE_LIMIT] = {EVENT_NONE, ...};
new String:eventConfiguration[SCHEDULE_LIMIT][PLATFORM_MAX_PATH];
new eventSetupTime[SCHEDULE_LIMIT] = {DEFAULT_SETUP_TIME, ...};
new eventMinParticipants[SCHEDULE_LIMIT] = {DEFAULT_MINIMUM_PLAYERS, ...};
new eventMaxParticipants[SCHEDULE_LIMIT] = {DEFAULT_MAXIMUM_PLAYERS, ...};

public OnPluginStart()
{
	SQL_TConnect(sql_ConnectDatabase, SQL_DATABASE);	
	CreateTimer(5.0, CheckSchedule, _, TIMER_REPEAT);
	CheckSchedule(INVALID_HANDLE);
	
	RegConsoleCmd("sm_schedule", Command_Schedule);
}

public OnGameFrame()
{
	static timestamp = INVALID_TIMESTAMP;
	if(timestamp < GetTime())
	{
		ProcessScheduleList(timestamp);
		timestamp = GetTime();
	}
}

ProcessScheduleList(timestamp)
{
	for(new i=0; i < SCHEDULE_LIMIT; i++)
	{
		if(eventTimestamp[i] != INVALID_TIMESTAMP)
		{
			if(eventTimestamp[i] == timestamp)
			{
				FireServerEvent(eventType[i], eventConfiguration[i], eventSetupTime[i], eventMinParticipants[i], eventMaxParticipants[i]);
				ClearServerEvent(i);
			}
		}
	}
}

FireServerEvent(Event:event, const String:strConfiguration[], setuptime, minplayers, maxplayers)
{
	new result = -1;
	
	if(event == EVENT_ARENA) result = ParseArenaConfiguration(strConfiguration);
	else if(event == EVENT_QUIZ) result = ParseQuizConfiguration(strConfiguration);
	else if(event == EVENT_SPYCRAB) result = ParseSpycrabConfiguration(strConfiguration);
	//else if(event == EVENT_LONGJUMP) result = ParseLongJumpConfiguration(strConfiguration);
	//else if(event == EVENT_HIGHJUMP) result = ParseHighJumpConfiguration(strConfiguration);
	//else if(event == EVENT_ASSAULTCOURSE) result = ParseAssaultCourseConfiguration(strConfiguration);
	//else if(event == EVENT_WALL) result = ParseWallConfiguration(strConfiguration);
	//else if(event == EVENT_DODGEBALL) result = ParseDodgeballConfiguration(strConfiguration);
	//else if(event == EVENT_SMASHER) result = ParseSmasherConfiguration(strConfiguration);
	//else if(event == EVENT_BLANK)	result = ParseBLANKConfiguration(strConfiguration);
	
	if(result == 0)
	{
		InitiateEventSetup(event, setuptime, minplayers, maxplayers);
	} else {
		SubmitToLog(LOG_ERROR, "Unable parse %s event configuration: '%s' (Result: %d)", g_strEvent[event], strConfiguration, result);
		CPrintToChatAll("{lawngreen}[SERVER]{default} Due to an error, the server was unable to start the %s event.", g_strEvent[event]);
		CPrintToChatAll("{lawngreen}[SERVER]{default} We apologise for any inconvenience this may have caused.", g_strEvent[event]);
	}
}

ClearServerEvent(index)
{
	eventTimestamp[index] = INVALID_TIMESTAMP;
	eventType[index] = EVENT_NONE;
	eventConfiguration[index] = "";
	eventSetupTime[index] = DEFAULT_SETUP_TIME;
	eventMinParticipants[index] = DEFAULT_MINIMUM_PLAYERS;
	eventMaxParticipants[index] = DEFAULT_MAXIMUM_PLAYERS;
}

public Action:CheckSchedule(Handle:timer)
{
	if(db != INVALID_HANDLE)
	{
		decl String:strQuery[256];
		Format(strQuery, sizeof(strQuery), "SELECT timestamp, event, configuration, setuptime, minplayers, maxplayers FROM event ORDER BY timestamp ASC LIMIT 0,%d", GetTime(), SCHEDULE_LIMIT);
		SQL_TQuery(db, sql_LoadEvent, strQuery, GetTime());
	}
	return Plugin_Continue;
}

public sql_ConnectDatabase(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl != INVALID_HANDLE)
	{
		db = hndl;
		
		decl String:strQuery[256];
		Format(strQuery, sizeof(strQuery), "CREATE TABLE IF NOT EXISTS event (timestamp INTEGER, event INTEGER, configuration TEXT, setuptime INTEGER, minplayers INTEGER, maxplayers INTEGER);");
		SQL_TQuery(db, sql_CreateTable, strQuery);
	} else {
		SubmitToLog(LOG_ERROR, "Unable to connect to SQL database: '%s' (Error: %s)", SQL_DATABASE, error);
		SetFailState("Unable to connect to SQL database. (Error: %s)", error);
	}
}

public sql_CreateTable(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl == INVALID_HANDLE)
	{
		SubmitToLog(LOG_ERROR, "Unable to create 'event' table. (Error: %s)", error);
		SetFailState("Unable to create table. (Error: %s)", error);
	}
}

public sql_LoadEvent(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl != INVALID_HANDLE)
	{
		new i=0;
		while(SQL_FetchRow(hndl))
		{
			ClearServerEvent(i);
			
			eventTimestamp[i] = SQL_IsFieldNull(hndl, 0) ? INVALID_TIMESTAMP : SQL_FetchInt(hndl, 0);
			eventType[i] = SQL_IsFieldNull(hndl, 1) ? EVENT_NONE : Event:SQL_FetchInt(hndl, 1);
			eventSetupTime[i] = SQL_IsFieldNull(hndl, 3) ? DEFAULT_SETUP_TIME : SQL_FetchInt(hndl, 3);
			eventMinParticipants[i] = SQL_IsFieldNull(hndl, 4) ? DEFAULT_MINIMUM_PLAYERS : SQL_FetchInt(hndl, 4);
			eventMaxParticipants[i] = SQL_IsFieldNull(hndl, 5) ? DEFAULT_MAXIMUM_PLAYERS : SQL_FetchInt(hndl, 5);
			
			if(SQL_IsFieldNull(hndl, 2)) {
				eventConfiguration[i] = "";
			} else {
				SQL_FetchString(hndl, 2, eventConfiguration[i], PLATFORM_MAX_PATH);
			}
			
/* 			if(eventTimestamp[i] <= data || _:eventType[i] <= 0 || _:eventType[i] > 10 || StrEqual(eventConfiguration[i], "", false))
			{
				SubmitToLog(LOG_ERROR, "Invalid event settings: Timestamp: %d | Type: %d | Configuration: %s", eventTimestamp[i], eventType[i], eventConfiguration[i]);
				continue;
			} */
			
			i++;
		}
	} else {
		SubmitToLog(LOG_ERROR, "SQL database query failed. (Error: %s)", error)
	}
}

public Action:Command_Schedule(client, args)
{
	DisplayScheduleMenu(client);
	return Plugin_Handled;
}

bool:DisplayScheduleMenu(client)
{
	new Handle:menu = CreateMenu(Schedule_Callback, MENU_ACTIONS_DEFAULT);
	if(menu != INVALID_HANDLE)
	{
		decl String:strText[128], String:strTime[128];
		
		new currentTime = GetTime();
		new timestamp = INVALID_TIMESTAMP;
		
		SetMenuTitle(menu, "[Enterprise] Event Schedule:");
		for(new i=0; i < SCHEDULE_LIMIT; i++)
		{
			timestamp = eventTimestamp[i];
			if(timestamp > GetTime())
			{
				decl String:strIndex[4];
				IntToString(i, strIndex, sizeof(strIndex));
				
				if(CompareTimeFormat(currentTime, timestamp, "%d %m %Y")) {
					FormatTime(strTime, sizeof(strTime), "Today @ %I:%M%p", timestamp);
				} 
				else if(CompareTimeFormat(currentTime + 86400, timestamp, "%d %m %Y")) {
					FormatTime(strTime, sizeof(strTime), "Tommorow @ %I:%M%p", timestamp);
				} else {
					FormatTime(strTime, sizeof(strTime), "%d/%m/%Y @ %I:%M%p", timestamp);
				}
				
				Format(strText, sizeof(strText), "[%s] - %s", g_strEvent[eventType[i]], strTime);
				AddMenuItem(menu, strIndex, strText);
			}
		}
		
		SetMenuPagination(menu, 8);
		SetMenuExitButton(menu, true);
		
		DisplayMenu(menu, client, MENU_TIME_FOREVER);
		return true;
	}
	return false;
}

public Schedule_Callback(Handle:menu, MenuAction:action, client, param)
{
	if(action == MenuAction_Select)
	{
		decl String:strSelection[4];
		GetMenuItem(menu, param, strSelection, sizeof(strSelection));
		new index = StringToInt(strSelection);
	
		new Handle:panel = CreatePanel(INVALID_HANDLE);
		if(panel != INVALID_HANDLE)
		{
			decl String:strText[128], String:strTime[128];
			SetPanelTitle(panel, "[Enterprise] Event Information:");
			
			DrawPanelItem(panel, "", ITEMDRAW_SPACER|ITEMDRAW_RAWLINE);
			
			Format(strText, sizeof(strText), "Event: %s", g_strEvent[eventType[index]]);
			DrawPanelText(panel, strText);
			
			DrawPanelItem(panel, "", ITEMDRAW_SPACER|ITEMDRAW_RAWLINE);
			
			FormatTime(strTime, sizeof(strTime), "Date: %d/%m/%Y", eventTimestamp[index]);
			DrawPanelText(panel, strTime);
			
			FormatTime(strTime, sizeof(strTime), "Time: %I:%M%p", eventTimestamp[index]);
			DrawPanelText(panel, strTime);
		
			DrawPanelItem(panel, "", ITEMDRAW_SPACER|ITEMDRAW_RAWLINE);
			
			Format(strText, sizeof(strText), "Minimum Players: %d", eventMinParticipants[index]);
			DrawPanelText(panel, strText);
			
			Format(strText, sizeof(strText), "Maximum Players: %d", eventMaxParticipants[index]);
			DrawPanelText(panel, strText);
			
			DrawPanelItem(panel, "", ITEMDRAW_SPACER|ITEMDRAW_RAWLINE);
			DrawPanelItem(panel, "Back");
			DrawPanelItem(panel, "Exit");
			SendPanelToClient(panel, client, Information_Callback, MENU_TIME_FOREVER);
		}
		CloseHandle(panel);
	}
	return;
}

public Information_Callback(Handle:menu, MenuAction:action, client, param)
{
	if(action == MenuAction_Select)
	{
		if(param == 1) {
			DisplayScheduleMenu(client);
		}
	}
	return;
}

public sql_DeleteEvent(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl == INVALID_HANDLE) {
		SubmitToLog(LOG_ERROR, "SQL database query failed. (Error: %s)", error)
	}
}

stock bool:CompareTimeFormat(timestamp1, timestamp2, String:strFormat[])
{
	decl String:strTime[2][128];
	
	FormatTime(strTime[0], 128, strFormat, timestamp1);
	FormatTime(strTime[1], 128, strFormat, timestamp2);
	
	if(StrEqual(strTime[0], strTime[1], false)) {
		return true;
	}
	return false;
}