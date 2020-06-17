#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.1"

#include <sourcemod>
#include <cstrike>
#include <voiceannounce_ex>

Database g_hDatabase;

Handle g_cDebug;
Handle g_cOnlyAdmins;
Handle g_cDatabase;

int g_iMinutes;
int g_iHours;
float g_fSeconds;

float g_fSpeaking[MAXPLAYERS + 1];

enum struct g_eTalkTime
{
	float Alive;
	float Dead;
	float T;
	float Ct;
	float Spec;
	float Total;
}

g_eTalkTime g_fTalkTime[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name = "MINFAS Talk Time",
	author = "MINFAS",
	description = "Saves how much players are speaking",
	version = PLUGIN_VERSION,
	url = "https://steamcommunity.com/id/minfas"
};

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("talktime.phrases");
	g_cDebug = CreateConVar("sm_talktime_debug", "0", "Show debug messages in client console?", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cOnlyAdmins = CreateConVar("sm_talktime_onlyadmins", "0", "Only admins can see stats of others?", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cDatabase = CreateConVar("sm_talktime_database", "talktime", "Which database (from databases.cfg) should be used?", FCVAR_PROTECTED);
	
	RegConsoleCmd("sm_talktime", Command_TalkTime, "Show information in menu");
	
	HookEvent("player_death", Event_Cut, EventHookMode_Pre);
	HookEvent("player_spawn", Event_Cut, EventHookMode_Pre);
	HookEvent("player_team", Event_Cut, EventHookMode_Pre);
}

public void OnPluginEnd()
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i))
		{
			SendValues(i);
		}
	}
}

public void OnConfigsExecuted()
{
	char db[32];
	GetConVarString(g_cDatabase, db, sizeof(db));
	Database.Connect(SQL_Connection, db);
}

public void SQL_Connection(Database hDatabase, const char[] szError, int iData)
{
	if(hDatabase == null)
	{
		ThrowError(szError);
	}
	else
	{
		g_hDatabase = hDatabase;	
		g_hDatabase.Query(SQL_Error, "CREATE TABLE IF NOT EXISTS `sm_talktime` ( `id` INT NOT NULL AUTO_INCREMENT , `name` VARCHAR(128) NOT NULL , `steamid` VARCHAR(32) NOT NULL , `total` FLOAT NOT NULL DEFAULT '0' , `alive` FLOAT NOT NULL DEFAULT '0' , `dead` FLOAT NOT NULL DEFAULT '0' , `t` FLOAT NOT NULL DEFAULT '0' , `ct` FLOAT NOT NULL DEFAULT '0' , `spec` FLOAT NOT NULL DEFAULT '0' , PRIMARY KEY (`id`))");
		g_hDatabase.SetCharset("utf8mb4");
   	}
   	
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i))
		{
			ClientCheck(i);
		}
	}
	
	if(GetConVarBool(g_cDebug) == true)
	{
		PrintToServer("[TalkTime debug] SQL Connected.");
	}
}

public void SQL_Error(Database hDatabase, DBResultSet hResults, const char[] szError, int iData)
{
    if(hResults == null)
    {
        ThrowError(szError);
    }
}

public void OnClientPostAdminCheck(int client)
{
	ClientCheck(client);
}

void ClientCheck(int client)
{
	char szSteamId[18];
	char szQuery[256];
	
	GetClientAuthId(client, AuthId_SteamID64, szSteamId, sizeof(szSteamId));
	g_hDatabase.Format(szQuery, sizeof(szQuery), "SELECT * FROM `sm_talktime` WHERE `steamid`='%s'", szSteamId);
	
	DataPack pack = new DataPack();
	
	pack.WriteString(szSteamId);
	pack.WriteCell(GetClientUserId(client));

	g_hDatabase.Query(SQL_ClientCheck, szQuery, pack);
}

public void SQL_ClientCheck(Database hDatabase, DBResultSet hResults, const char[] szError, DataPack pack)
{
	if(hResults == null)
	{
		ThrowError(szError);
	}
	
	char szQuery[256];
	char szSteamId[18];
	char szName[MAX_NAME_LENGTH];
	char szDbName[MAX_NAME_LENGTH];
	
	pack.Reset();
	pack.ReadString(szSteamId, sizeof(szSteamId));
	int client = GetClientOfUserId(pack.ReadCell());
	
	delete pack;
	
	GetClientName(client, szName, sizeof(szName));
	
	if(hResults.RowCount != 0)
	{
		hResults.FetchRow();
		hResults.FetchString(1, szDbName, sizeof(szDbName));
		
		if(!StrEqual(szDbName, szName, true))
		{
			g_hDatabase.Format(szQuery, sizeof(szQuery), "UPDATE `sm_talktime` SET `name`='%s' WHERE `steamid`='%s'", szName, szSteamId);
			g_hDatabase.Query(SQL_Error, szQuery);
		}
		
		g_fTalkTime[client].Alive = hResults.FetchFloat(4);
		g_fTalkTime[client].Dead = hResults.FetchFloat(5);
		g_fTalkTime[client].T = hResults.FetchFloat(6);
		g_fTalkTime[client].Ct = hResults.FetchFloat(7);
		g_fTalkTime[client].Spec = hResults.FetchFloat(8);
		g_fTalkTime[client].Total = hResults.FetchFloat(3);
	}
	else
	{
		ClearValues(client);

		g_hDatabase.Format(szQuery, sizeof(szQuery), "INSERT INTO `sm_talktime` (name, steamid) VALUES ('%s', '%s')", szName, szSteamId);
		g_hDatabase.Query(SQL_Error, szQuery);
	}
}

public void OnClientDisconnect(int client)
{
	SendValues(client);
}

void SendValues(int client)
{
	char szSteamId[18];
	char szQuery[256];
	char szName[MAX_NAME_LENGTH];

	GetClientAuthId(client, AuthId_SteamID64, szSteamId, sizeof(szSteamId));
	GetClientName(client, szName, sizeof(szName));

	g_hDatabase.Format(szQuery, sizeof(szQuery), "UPDATE `sm_talktime` SET `name`='%s', `total`='%f', `alive`='%f', `dead`='%f', `t`='%f', `ct`='%f', `spec`='%f' WHERE `steamid`='%s'", szName, g_fTalkTime[client].Total, g_fTalkTime[client].Alive, g_fTalkTime[client].Dead, g_fTalkTime[client].T, g_fTalkTime[client].Ct, g_fTalkTime[client].Spec, szSteamId);
	g_hDatabase.Query(SQL_Error, szQuery);

	// probably not necessary but make sure everything is cleared.
	ClearValues(client);
}

void ClearValues(int client)
{
	g_fTalkTime[client].Alive = 0.0;
	g_fTalkTime[client].Dead = 0.0;
	g_fTalkTime[client].T = 0.0;
	g_fTalkTime[client].Ct = 0.0;
	g_fTalkTime[client].Spec = 0.0;
	g_fTalkTime[client].Total = 0.0;
	g_fSpeaking[client] = 0.0;
}

public Action Command_TalkTime(int client, int args)
{
	if (args < 1 || (GetConVarBool(g_cOnlyAdmins) == true && !CheckCommandAccess(client, "", ADMFLAG_GENERIC, true)))
	{
		TalkTimeMenu(client, client);
		return Plugin_Handled;
	}
	else if((GetConVarBool(g_cOnlyAdmins) == true && CheckCommandAccess(client, "", ADMFLAG_GENERIC, true)) || GetConVarBool(g_cOnlyAdmins) == false)
	{
		char arg1[32];
		GetCmdArg(1, arg1, 32);
	   
		char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS]; 
		int target_count; 
		bool tn_is_ml;
	   
		target_count = ProcessTargetString(arg1, client, target_list, MAXPLAYERS, COMMAND_FILTER_CONNECTED, target_name, sizeof(target_name), tn_is_ml);
	   
		if (target_count < 1)
		{
			ReplyToCommand(client, "%t", "No matching clients");
			return Plugin_Handled;
		}
	   
		if (target_count == 1)
		{
			TalkTimeMenu(client, target_list[0]);
			return Plugin_Handled;
		}
		
		Menu menu = new Menu(hListMenu, MENU_ACTIONS_ALL);
		menu.SetTitle("%t", "More than one client matched");
		for (int i = 0; i < target_count; i++)
		{
			if(IsValidClient(target_list[i]))
			{
				char buffer[128], timer[32], targetid[3];
				
				ShowTimer(g_fTalkTime[target_list[i]].Total, "", timer, sizeof(timer));
				Format(buffer, sizeof(buffer), "%N (%s)", target_list[i], timer); //pst..
				IntToString(target_list[i], targetid, sizeof(targetid));
				
				menu.AddItem(targetid, buffer);
			}
		}
		menu.Display(client, MENU_TIME_FOREVER);
	}
	return Plugin_Handled;
}

public int hListMenu(Menu menu, MenuAction action, int client, int index)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			if(IsValidClient(client))
			{
				char szItem[64];
				menu.GetItem(index, szItem, sizeof(szItem));
				TalkTimeMenu(client, StringToInt(szItem));
			}
		}
	}
}

void TalkTimeMenu(int client, int talker)
{
	char buffer[128], info[32];
	Panel menu = CreatePanel();
	Format(buffer, sizeof(buffer), "%t", "My talk time", LANG_SERVER, talker);
	Format(info, sizeof(info), "%t", "Talk time", LANG_SERVER, talker);
	menu.SetTitle((talker == client)?buffer:info);
	
	Format(info, sizeof(info), "%t", "Total Talk Time", LANG_SERVER);
	ShowTimer(g_fTalkTime[talker].Total, info, buffer, sizeof(buffer));
	menu.DrawText(buffer);

	Format(info, sizeof(info), "%t", "Alive", LANG_SERVER);
	ShowTimer(g_fTalkTime[talker].Alive, info, buffer, sizeof(buffer));
	menu.DrawText(buffer);
	
	Format(info, sizeof(info), "%t", "Dead", LANG_SERVER);
	ShowTimer(g_fTalkTime[talker].Dead, info, buffer, sizeof(buffer));
	menu.DrawText(buffer);
	
	Format(info, sizeof(info), "%t", "Ct", LANG_SERVER);
	ShowTimer(g_fTalkTime[talker].Ct, info, buffer, sizeof(buffer));
	menu.DrawText(buffer);
	
	Format(info, sizeof(info), "%t", "T", LANG_SERVER);
	ShowTimer(g_fTalkTime[talker].T, info, buffer, sizeof(buffer));
	menu.DrawText(buffer);
	
	Format(info, sizeof(info), "%t", "Spec", LANG_SERVER);
	ShowTimer(g_fTalkTime[talker].Spec, info, buffer, sizeof(buffer));
	menu.DrawText(buffer);

	Format(info, sizeof(info), "%t", "Close menu", LANG_SERVER);
	menu.DrawItem(info, ITEMDRAW_DEFAULT);
	menu.Send(client, hTalkTimeMenu, MENU_TIME_FOREVER);
}

public int hTalkTimeMenu(Menu menu, MenuAction action, int client, int index)
{
	/*nothing*/
}

public void OnClientSpeakingEx(int client)
{
	if(g_fSpeaking[client] <= 0.0)
	{
		g_fSpeaking[client] = GetGameTime();
		if(GetConVarBool(g_cDebug) == true)
		{
			PrintToConsole(client, "[TalkTime debug] You started speaking.");
		}
	}
}

public void OnClientSpeakingEnd(int client)
{
	WriteValues(client, IsPlayerAlive(client));
}

public Action Event_Cut(Handle event, char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if(IsClientSpeaking(client))
	{
		WriteValues(client, false);
	}
}

void WriteValues(int client, bool alive)
{
	if(g_fSpeaking[client] > 0.01)
	{
		g_fSpeaking[client] = GetGameTime() - g_fSpeaking[client];
		
		if(GetConVarBool(g_cDebug) == true)
		{
			PrintToConsole(client, "[TalkTime debug] You spoke %.2f seconds. (Total: %.2f)", g_fSpeaking[client], g_fTalkTime[client].Total);
		}
		
		if(alive == true)
		{
			g_fTalkTime[client].Alive += g_fSpeaking[client];
		}
		else
		{
			g_fTalkTime[client].Dead += g_fSpeaking[client];
		}
		
		if(GetClientTeam(client) == CS_TEAM_T)
		{
			g_fTalkTime[client].T += g_fSpeaking[client];
		}
		else if(GetClientTeam(client) == CS_TEAM_CT)
		{
			g_fTalkTime[client].Ct += g_fSpeaking[client];
		}
		else if(GetClientTeam(client) == CS_TEAM_SPECTATOR)
		{
			g_fTalkTime[client].Spec += g_fSpeaking[client];
		}
		
		g_fTalkTime[client].Total += g_fSpeaking[client];
	}
	
	g_fSpeaking[client] = 0.0;	
}

int ShowTimer(float Time, char[] add, char[] buffer, int sizef)
{
	g_iHours = 0;
	g_iMinutes = 0;
	g_fSeconds = Time;
	
	char hours[16];
	char minutes[16];
	char seconds[16];
	
	Format(hours, sizeof(hours), "%t", "Hours");
	Format(minutes, sizeof(minutes), "%t", "Minutes");
	Format(seconds, sizeof(seconds), "%t", "Seconds");
	
	while(g_fSeconds > 3600.0)
	{
		g_iHours++;
		g_fSeconds -= 3600.0;
	}
	while(g_fSeconds > 60.0)
	{
		g_iMinutes++;
		g_fSeconds -= 60.0;
	}
	if(g_iHours >= 1)
	{
		Format(buffer, sizef, "%d %s %d %s %.0f %s", g_iHours, hours, g_iMinutes, minutes, g_fSeconds, seconds);
	}
	else if(g_iMinutes >= 1)
	{
		Format(buffer, sizef, "%d %s %.0f %s", g_iMinutes, minutes, g_fSeconds, seconds);
	}
	else
	{
		Format(buffer, sizef, "%.0f %s", g_fSeconds, seconds);
	}
	Format(buffer, sizef, "%s %s", add, buffer);
}

stock bool IsValidClient(int client)
{
	if(client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsClientSourceTV(client))
	{
		return true;
	}
	return false;
}