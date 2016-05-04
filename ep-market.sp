#include <sourcemod>
#include <enterprise>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION		"1.0.0"
#define SQL_DATABASE		"enterprise-database"

#define SOUND_PICKUP		"mvm/mvm_money_pickup.wav"
#define SOUND_VANISH		"mvm/mvm_money_vanish.wav"

#define MAX_CATEGORIES		64
#define MAX_PRODUCTS		128

// Shop
new String:g_strCategory[MAX_CATEGORIES][32];
new String:g_strProduct[MAX_CATEGORIES][MAX_PRODUCTS][32];

new Handle:db = INVALID_HANDLE;
new Handle:gConVar[10] = {INVALID_HANDLE, ...};

new gCurrency[MAXPLAYERS+1] = {0, ...};
new gRecent[MAXPLAYERS+1] = {0, ...};
new gBonus[MAXPLAYERS+1] = {0, ...};

new Handle:hHudCurrency = INVALID_HANDLE;
new Handle:hHudRecent = INVALID_HANDLE;
new Handle:hHudBonus = INVALID_HANDLE;

public Plugin:myinfo = 
{
	name = "Enterprise - Market",
	author = PLUGIN_AUTHOR,
	description = "",
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	// Natives:
	CreateNative("CreateCash", Native_CreateCash);
	
	CreateNative("AdjustClientCurrency", Native_AdjustClientCurrency);
	CreateNative("GetClientCurrency", Native_GetClientCurrency);
}

public OnPluginStart()
{
	SQL_TConnect(cb_ConnectDatabase, SQL_DATABASE);
	
	gConVar[0] = CreateConVar("sm_cash_ground", "1", "Whether or not money will drop to the ground when spawned.");
	ServerCommand("sv_hudhint_sound 0");
	
	hHudCurrency = CreateHudSynchronizer();
	hHudRecent = CreateHudSynchronizer();
	hHudBonus = CreateHudSynchronizer();
	
	//Debug
	RegAdminCmd("sm_adjustcurrency", Command_Adjust, ADMFLAG_ROOT);
	RegAdminCmd("sm_createcash", Command_Cash, ADMFLAG_ROOT);
	
	RegConsoleCmd("sm_shop", Command_Shop);
	RegConsoleCmd("sm_market", Command_Shop);
	RegConsoleCmd("sm_buy", Command_Shop);
}

public OnMapStart()
{
	PrecacheSound(SOUND_PICKUP);
	PrecacheSound(SOUND_VANISH);
}

public Action:Command_Shop(client, args)
{
	if(!ShowMenu(client, 0)) {
		ReplyToCommand(client, "[Mann Co.] Unable to display shop menu.");
	}
	return Plugin_Handled;
}

bool:ShowMenu(any:client, menuid, any:id=0)
{
	switch(menuid)
	{
		case 0: // Main Menu
		{
			new Handle:panel = CreatePanel(INVALID_HANDLE);
			if(panel != INVALID_HANDLE)
			{
				decl String:strText[128];
				SetPanelTitle(panel, "[Mann Co.] Main Menu:");
				
				Format(strText, sizeof(strText), "You currently have: $%d", gCurrency[client]);
				DrawPanelText(panel, strText);
				
				DrawPanelItem(panel, "", ITEMDRAW_SPACER|ITEMDRAW_RAWLINE);
				DrawPanelItem(panel, "Reward Shop");
				DrawPanelItem(panel, "Bonus Cash");
				DrawPanelItem(panel, "", ITEMDRAW_SPACER|ITEMDRAW_RAWLINE);
				DrawPanelItem(panel, "Exit");
				
				SendPanelToClient(panel, client, Main_Callback, MENU_TIME_FOREVER);
				
				CloseHandle(panel);
				return true;
			} else {
				return false;
			}
		}
		case 1: // Bonus Cash
		{
			new Handle:panel = CreatePanel(INVALID_HANDLE);
			if(panel != INVALID_HANDLE)
			{
				decl String:strText[128];
				SetPanelTitle(panel, "[Enterprise] Bonus Cash:");
				
				DrawPanelItem(panel, "", ITEMDRAW_SPACER|ITEMDRAW_RAWLINE);
				DrawPanelText(panel, "Being a member of our Steam Group grants extra cash");
				DrawPanelText(panel, "whenever you earn some normally. The bonus recieved");
				DrawPanelText(panel, "is a percentage of the number of members there are.");
				DrawPanelItem(panel, "", ITEMDRAW_SPACER|ITEMDRAW_RAWLINE);
				
				Format(strText, sizeof(strText), "Current Bonus: %d / 100 = %0.f%", GetGroupMemberCount(), GetGroupMemberCount() / 100.0);
				DrawPanelText(panel, strText);
				
				Format(strText, sizeof(strText), "Current Status: %s", GetClientGroupMembership(client) <= 0 ? "You are NOT eligible to recieve cash bonuses." : "You are eligible to recieve cash bonuses.");
				DrawPanelText(panel, strText);
				
				DrawPanelItem(panel, "", ITEMDRAW_SPACER|ITEMDRAW_RAWLINE);
				DrawPanelItem(panel, "[PRINT] Steam Group URL");
				DrawPanelItem(panel, "", ITEMDRAW_SPACER|ITEMDRAW_RAWLINE);
				DrawPanelItem(panel, "Back");
				DrawPanelItem(panel, "Exit");
				SendPanelToClient(panel, client, Bonus_Callback, MENU_TIME_FOREVER);
				
				CloseHandle(panel);
				return true;
			} else {
				return false;
			}
		}
/* 		case 2: 
		{
			new Handle:menu = CreateMenu(Shop_Callback, MENU_ACTIONS_DEFAULT);
			if(menu != INVALID_HANDLE)
			{
				decl String:strText[128];
				SetMenuTitle(menu, "[Enterprise] Shop Catagories:");
				
 				for(new i=0; i < sizeof(g_strCategory), i++)
				{
					if(!StrEqual(g_strCategory[i], "", false) && CountProducts(i) != 0)
					{
						decl String:strIndex[4];
						IntToString(i, strIndex, sizeof(strIndex));
						
						Format(strText, sizeof(strText), "%s [%d Items]", g_strCategory[i], CountProducts(i));
						AddMenuItem(menu, strIndex, strText);
					} else continue;
				}
				
				SetMenuPagination(menu, 8);
				SetMenuExitButton(menu, true);
				
				DisplayMenu(menu, client, MENU_TIME_FOREVER);
				return true;
				
			} else {
				return false;
			}
		} */
/* 		case 3: 
		{
			new Handle:menu = CreateMenu(Product_Callback, MENU_ACTIONS_DEFAULT);
			if(menu != INVALID_HANDLE)
			{
				decl String:strText[128];
				
				Format(strText, sizeof(strText), "[Mann Co.] %s:", g_strCatagory[id]);
				SetMenuTitle(menu, strText);
				
				for(new i=0; i < sizeof(g_strProduct[]), i++)
				{
					if(!StrEqual(g_strProduct[id][i], "", false))
					{
						decl String:strIndex[4];
						IntToString(i, strIndex, sizeof(strIndex));
						
						Format(strText, sizeof(strText), "%s ($%d)", g_strProduct[id][i], g_ProductCost[id][i]));
						AddMenuItem(menu, strIndex, strText);
					} else continue;
				}
				
				SetMenuPagination(menu, 8);
				SetMenuExitButton(menu, true);
				
				DisplayMenu(menu, client, MENU_TIME_FOREVER);
				return true;
				
			} else {
				return false;
			}
		} */
		default: return false;
	}
	return false;
}

public Main_Callback(Handle:menu, MenuAction:action, client, param)
{
	if(action == MenuAction_Select)
	{
		if(param == 1) return;
		if(param == 2)
		{
			if(!ShowMenu(client, 1)) {
				PrintToChat(client, "[Mann Co.] Unable to display menu.");
			}
		} else return;
	}
	return;
}

public Bonus_Callback(Handle:menu, MenuAction:action, client, param)
{
	if(action == MenuAction_Select)
	{
		if(param == 1) 
		{
			PrintToChat(client, "");
			PrintToChat(client, "[Enterprise] Steam Group URL:");
			PrintToChat(client, "http://steamcommunity.com/groups/Mannco-lottery");
			PrintToChat(client, "");
		}
		if(param == 2)
		{
			if(!ShowMenu(client, 0)) {
				PrintToChat(client, "[Mann Co.] Unable to display menu.");
			}
		} else return;
	}
	return;
}

public Shop_Callback(Handle:menu, MenuAction:action, client, param)
{
	if(action == MenuAction_Select)
	{
		decl String:strSelection[4];
		GetMenuItem(menu, param, strSelection, sizeof(strSelection));
		
		new index = StringToInt(strSelection);
	}
	return;
}

public Action:DisplayTimer(Handle:timer, any:client)
{
	if(IsValidClient(client))
	{
		if(IsPlayerAlive(client))
		{
			SetHudTextParams(-0.615, -0.07, 0.175, 255, 215, 0, 255);
			ShowSyncHudText(client, hHudCurrency, "Credits: $%d", gCurrency[client]);
			
			if(gRecent[client] != 0)
			{
				if(gRecent[client] >= 1)
				{
					SetHudTextParams(-0.615, -0.04, 3.0, 0, 255, 0, 255);
					ShowSyncHudText(client, hHudRecent, "+%d", gRecent[client]);
				} else {
					SetHudTextParams(-0.615, -0.04, 3.0, 255, 0, 0, 255);
					ShowSyncHudText(client, hHudRecent, "%d", gRecent[client]);
				}
				gRecent[client] = 0;
			}
			
			if(gBonus[client] != 0)
			{
				SetHudTextParams(-0.615, -0.01, 3.0, 0, 0, 255, 255);
				ShowSyncHudText(client, hHudBonus, "Bonus: +%d", gBonus[client]);
				gBonus[client] = 0;
			}
		}
		CreateTimer(0.1, DisplayTimer, client);
	}
}

public OnEntityCreated(entity, const String:strClassname[])
{
	if(GetConVarInt(gConVar[0]) >= 1)
	{
		if(StrContains(strClassname, "item_currencypack_", false) != -1) {
			RequestFrame(OnCashSpawn, EntIndexToEntRef(entity));
		}
	}
}

public OnCashSpawn(any:ref)
{
	new entity = EntRefToEntIndex(ref);
	if(IsValidEdict(entity))
	{
		new Float:vecOrigin[3];
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", vecOrigin);
		
		//vecOrigin[2] -= GetDistanceFromGround(entity);
		TeleportEntity(entity, vecOrigin, NULL_VECTOR, NULL_VECTOR);
	}
}

public Action:Command_Adjust(client, args)
{
	decl String:arg1[8], String:arg2[8];
	
	GetCmdArg(1, arg1, sizeof(arg1));
	GetCmdArg(2, arg2, sizeof(arg2));
	
	new value = StringToInt(arg1);
	new set = StringToInt(arg2);
	
	AdjustClientCurrency(client, value, bool:set);
	
	return Plugin_Handled;
}

public cb_ConnectDatabase(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl != INVALID_HANDLE)
	{
		db = hndl;
		
		decl String:strQuery[256];
		Format(strQuery, sizeof(strQuery), "CREATE TABLE IF NOT EXISTS currency (auth TEXT, amount INTEGER);");
		SQL_TQuery(db, cb_CreateTable, strQuery);
	} else {
		SubmitToLog(LOG_ERROR, "Unable to connect to SQL database: '%s' (Error: %s)", SQL_DATABASE, error);
		SetFailState("Unable to connect to SQL database. (Error: %s)", error);
	}
}

public cb_CreateTable(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl != INVALID_HANDLE)
	{
		for(new i=1; i <= MaxClients; i++) // This'll only matter if the plugin was loaded in the middle of gameplay.
		{
			if(IsValidClient(i)) {
				LoadClient(i);
			}
		}
	} else {
		SubmitToLog(LOG_ERROR, "Unable to create 'currency' table. (Error: %s)", error);
		SetFailState("Unable to create table. (Error: %s)", error);
	}
}

public OnClientPostAdminCheck(client)
{
	LoadClient(client);
}

public OnClientDisconnect(client)
{
	if(IsValidClient(client))
	{
		SaveClient(client, true);
	}
}

CreateClient(client)
{
	decl String:strQuery[256], String:strAuth[32];
	
	GetClientAuthId(client, AuthId_Steam2, strAuth, sizeof(strAuth));
	Format(strQuery, sizeof(strQuery), "INSERT INTO currency (auth, amount) VALUES ('%s', 0)", strAuth);
	SQL_TQuery(db, cb_CreateClient, strQuery, GetClientUserId(client));
}

public cb_CreateClient(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl != INVALID_HANDLE)
	{
		new client = GetClientOfUserId(data);
		if(IsValidClient(client)) {
			gCurrency[client] = 0;
		}
	} else {
		SubmitToLog(LOG_ERROR, "SQL database query failed. (Error: %s)", error);
	}
}

LoadClient(client)
{
	decl String:strQuery[256], String:strAuth[32];
	
	GetClientAuthId(client, AuthId_Steam2, strAuth, sizeof(strAuth));
	Format(strQuery, sizeof(strQuery), "SELECT amount FROM currency WHERE auth='%s'", strAuth);
	SQL_TQuery(db, cb_LoadClient, strQuery, GetClientUserId(client));
}

public cb_LoadClient(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl != INVALID_HANDLE)
	{
		new client = GetClientOfUserId(data);
		if(IsValidClient(client))
		{
			if(SQL_GetRowCount(hndl)) // Query completed successfully, results were found.
			{
				gCurrency[client] = SQL_FetchInt(hndl, 0);
				if(gCurrency[client] < 0) gCurrency[client] = 0;
			} else { // Query completed successfully, but no results were found.
				CreateClient(client);
			}
			CreateTimer(1.0, DisplayTimer, client);
		}
	} else {
		SubmitToLog(LOG_ERROR, "SQL database query failed. (Error: %s)", error);
	}
}

SaveClient(client, bool:clear=false)
{
	decl String:strQuery[256], String:strAuth[32];
	
	GetClientAuthId(client, AuthId_Steam2, strAuth, sizeof(strAuth));
	Format(strQuery, sizeof(strQuery), "UPDATE currency SET amount=%d WHERE auth='%s'", gCurrency[client], strAuth);
	
	if(clear) SQL_TQuery(db, cb_CreateClient, strQuery, 0);
	else SQL_TQuery(db, cb_CreateClient, strQuery, client);
}

public cb_SaveClient(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl != INVALID_HANDLE)
	{
		if(SQL_GetRowCount(hndl))
		{
			if(data != 0) gCurrency[data] = 0;
		} else {
			SubmitToLog(LOG_ERROR, "Unable to save client information.");
		}
	} else {
		SubmitToLog(LOG_ERROR, "SQL database query failed. (Error: %s)", error);
	}
}

public Action:Command_Cash(client, args)
{
	new Float:vecOrigin[3], String:arg1[8], String:arg2[4];
	
	GetCmdArg(1, arg1, sizeof(arg1));
	GetCmdArg(2, arg2, sizeof(arg2));
	
	new value = StringToInt(arg1);
	new type = StringToInt(arg2);
	
	CreateCash(vecOrigin, value, type);
	return Plugin_Handled;
}

public Native_CreateCash(Handle:plugin, numParams)
{
	decl String:strEntity[32];
	
	new type = GetNativeCell(3);
	if(type == 0) type = GetRandomInt(1, 3);
	switch(type)
	{
		case 1: strEntity = "item_currencypack_small";
		case 2: strEntity = "item_currencypack_medium";
		case 3: strEntity = "item_currencypack_large";
		default: strEntity = "item_currencypack_small";
	}
	
	new entity = CreateEntityByName(strEntity);
	if(IsValidEdict(entity))
	{
		decl String:strValue[8], Float:vecOrigin[3];
		GetNativeArray(1, vecOrigin, 3);
		
		new value = GetNativeCell(2);
		IntToString(value, strValue, sizeof(strValue));
		DispatchKeyValue(entity, "targetname", strValue);
		
		SDKHook(entity, SDKHook_Touch, OnCashTouch);
		
		DispatchSpawn(entity);
		TeleportEntity(entity, vecOrigin, NULL_VECTOR, NULL_VECTOR);
		
		return entity;
	}
	return -1;
}

public OnCashTouch(entity, client)
{
	if(IsValidClient(client))
	{
		SDKUnhook(entity, SDKHook_Touch, OnCashTouch);
		
		decl String:strValue[8];
		GetEntPropString(entity, Prop_Data, "m_iName", strValue, sizeof(strValue));
		
		new value = StringToInt(strValue);
		AdjustClientCurrency(client, value, false);
		
		AcceptEntityInput(entity, "Kill");
	}
}

public Native_AdjustClientCurrency(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	new value = GetNativeCell(2);
	
	if(GetNativeCell(3)) gCurrency[client] = value;
	else 
	{
		gRecent[client] = value;
		if(value > 0) {
			gBonus[client] = CalculateGroupBonus(client, value);
			gCurrency[client] += value + gBonus[client];
		} else gCurrency[client] += value;
	}
	
	if(gCurrency[client] < 0) {
		gCurrency[client] = 0;
	}
	
	SaveClient(client, false);
}

CalculateGroupBonus(client, value)
{
	if(GetClientGroupMembership(client) > 0)
	{
		new Float:flMult = GetGroupMemberCount() / 100.0 / 100.0;
		
		new String:strMult[8];
		Format(strMult, sizeof(strMult), "%0.f", value * flMult);
		
		return StringToInt(strMult);
	}
	return 0;
}

CountProducts(category)
{
	new x = 0;
	for(new i=0; i < sizeof(g_strProduct[category]); i++) {
		if(!StrEqual(g_strProduct[category][i], "", false) x++;
	}
	return x;
}

public Native_GetClientCurrency(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	return gCurrency[client];
}