#include <amxmodx>
#include <reapi>

#define NAMES_LENGTH				28
#define is_user_valid(%0)			(0 < %0 && %0 < g_iMaxPlayers)

// TODO: Доинтегрировать к микс системе, поддержка AirBlock

enum _:PLAYER_DATA
{
	DAMAGE_ON[33],
	Float:DAMAGE_ON_TIME[33],
	NAME[32]
}
new g_ePlayerData[33][PLAYER_DATA], g_iMaxPlayers, g_iMsgScoreInfo
new HookChain:g_pSV_WriteFullClientUpdate, HookChain:g_pCBasePlayer_Killed_Post, g_szDeathString[32], g_iAssistKiller

public plugin_natives()
{
	set_native_filter("plugin_native_filter")
}

public plugin_native_filter(szNative[], iIndex, bool:bTrap)
{
	return PLUGIN_HANDLED
}

public plugin_init()
{
	register_plugin("HNS: Kill Assists", "1.4", "OpenHNS") // Xelson

	RegisterHookChain(RG_CBasePlayer_Spawn, "CBasePlayer_Spawn_Post", true)
	RegisterHookChain(RG_CBasePlayer_Killed, "CBasePlayer_Killed_Pre", false)
	RegisterHookChain(RG_CBasePlayer_TakeDamage, "CBasePlayer_TakeDamage_Pre", false)
	DisableHookChain((g_pCBasePlayer_Killed_Post = RegisterHookChain(RG_CBasePlayer_Killed, "CBasePlayer_Killed_Post", true)))
	DisableHookChain((g_pSV_WriteFullClientUpdate = RegisterHookChain(RH_SV_WriteFullClientUpdate, "SV_WriteFullClientUpdate", false)))
	register_message(get_user_msgid("DeathMsg"), "Message_DeathMsg")

	#if defined DEBUG
		register_clcmd("assist", "ClCmd_Assist")
	#endif

	g_iMsgScoreInfo = get_user_msgid("ScoreInfo")
	g_iMaxPlayers = get_maxplayers() + 1
}

public client_infochanged(id)
{
	get_user_info(id, "name", g_ePlayerData[id][NAME], charsmax(g_ePlayerData[][NAME]))
}

public client_disconnected(id)
{
	arrayset(g_ePlayerData[id][DAMAGE_ON], 0, sizeof g_ePlayerData[][DAMAGE_ON])
	for(new i = 1; i < g_iMaxPlayers; i++) g_ePlayerData[i][DAMAGE_ON][id] = 0
}

public CBasePlayer_Spawn_Post(id)
{
	arrayset(g_ePlayerData[id][DAMAGE_ON], 0, sizeof g_ePlayerData[][DAMAGE_ON])
	for(new i = 1; i < g_iMaxPlayers; i++) g_ePlayerData[i][DAMAGE_ON][id] = 0
}

public CBasePlayer_TakeDamage_Pre(iVictim, iWeapon, iAttacker, Float:fDamage)
{
	if(is_user_valid(iAttacker) && iVictim != iAttacker && rg_is_player_can_takedamage(iVictim, iAttacker))
	{
		new Float:fHealth; get_entvar(iVictim, var_health, fHealth)
		if(fDamage > fHealth) fDamage = fHealth

		g_ePlayerData[iAttacker][DAMAGE_ON][iVictim] += floatround(fDamage)
		g_ePlayerData[iAttacker][DAMAGE_ON_TIME][iVictim] = get_gametime()
	}
}

public CBasePlayer_Killed_Pre(iVictim, iKiller)
{
	new iAssistant, iMaxDamage
	new Float:fDamageForAssist = 40.0

	new iTotalDamage
	for(new id = 1; id < g_iMaxPlayers; id++)
	{
		if(is_user_connected(id))
		{
			if(id != iKiller && g_ePlayerData[id][DAMAGE_ON][iVictim] > 0)
			{
				if(g_ePlayerData[id][DAMAGE_ON][iVictim] > iMaxDamage)
				{
					iAssistant = id
					iMaxDamage = g_ePlayerData[id][DAMAGE_ON][iVictim]
				}
				else if(g_ePlayerData[id][DAMAGE_ON][iVictim] == iMaxDamage) 
					iAssistant = g_ePlayerData[id][DAMAGE_ON_TIME][iVictim] > g_ePlayerData[iAssistant][DAMAGE_ON_TIME][iVictim] ? id : iAssistant
			}
			iTotalDamage += g_ePlayerData[id][DAMAGE_ON][iVictim]
		}
	}
	if((float(iMaxDamage) / float(iTotalDamage)) * 100.0 < fDamageForAssist) iAssistant = 0

	if(!iAssistant || iKiller == iVictim) return HC_CONTINUE

	new szName[2][32], iLen[2], iExcess
	copy(szName[1], charsmax(szName[]), g_ePlayerData[iAssistant][NAME])
	iLen[1] = strlen(szName[1])

	EnableHookChain(g_pSV_WriteFullClientUpdate)
	
	static const szWorldName[] = "world"
	new bool:bIsAssistantConnected = bool:is_user_connected(iAssistant)

	if(!is_user_valid(iKiller))
	{
		if(bIsAssistantConnected)
		{
			iExcess = iLen[1] - NAMES_LENGTH - (sizeof szWorldName)
			if(iExcess > 0) strclip(szName[1], iExcess)
			formatex(g_szDeathString, charsmax(g_szDeathString), "%s + %s", szWorldName, szName[1])

			g_iAssistKiller = iAssistant
			rh_update_user_info(iAssistant)
		}
	}
	else if(is_user_connected(iKiller))
	{
		g_ePlayerData[iKiller][DAMAGE_ON][iVictim] = 0
		
		copy(szName[0], charsmax(szName[]), g_ePlayerData[iKiller][NAME])
		iLen[0] = strlen(szName[0])

		new iLenSum = (iLen[0] + iLen[1])
		iExcess = iLenSum - NAMES_LENGTH

		if(iExcess > 0)
		{
			new iLongest = iLen[0] > iLen[1] ? 0 : 1
			new iShortest = iLongest == 1 ? 0 : 1

			if(float(iExcess) / float(iLen[iLongest]) > 0.60)
			{
				new iNewLongest = floatround(float(iLen[iLongest]) / float(iLenSum) * float(iExcess))
				strclip(szName[iLongest], iNewLongest)
				strclip(szName[iShortest], iExcess - iNewLongest)
			}
			else strclip(szName[iLongest], iExcess)
		}
		formatex(g_szDeathString, charsmax(g_szDeathString), "%s + %s", szName[0], szName[1])

		g_iAssistKiller = iKiller
		rh_update_user_info(g_iAssistKiller)
	}
	if(bIsAssistantConnected)
	{   
		g_ePlayerData[iAssistant][DAMAGE_ON][iVictim] = 0

		new Float:fNewFrags; get_entvar(iAssistant, var_frags, fNewFrags)
		fNewFrags++
		set_entvar(iAssistant, var_frags, fNewFrags)

		message_begin(MSG_ALL, g_iMsgScoreInfo)
		write_byte(iAssistant)
		write_short(floatround(fNewFrags))
		write_short(get_member(iAssistant, m_iDeaths))
		write_short(0)
		write_short(get_member(iAssistant, m_iTeam))
		message_end()
	}
	
	DisableHookChain(g_pSV_WriteFullClientUpdate)
	if(g_iAssistKiller) EnableHookChain(g_pCBasePlayer_Killed_Post)

	return HC_CONTINUE
}

public SV_WriteFullClientUpdate(id, pBuffer)
{
	if(id == g_iAssistKiller)
		set_key_value(pBuffer, "name", g_szDeathString)
}

public Message_DeathMsg()
{
	new iWorld = get_msg_arg_int(1)
	if(iWorld == 0 && g_iAssistKiller)
		set_msg_arg_int(1, ARG_BYTE, g_iAssistKiller)
}

public CBasePlayer_Killed_Post(iVictim, iKiller)
{
	DisableHookChain(g_pCBasePlayer_Killed_Post)

	new iAssistKiller = g_iAssistKiller; g_iAssistKiller = 0
	rh_update_user_info(iAssistKiller)
}

strclip(szString[], iClip, szEnding[] = "..")
{
	new iLen = strlen(szString) - 1 - strlen(szEnding) - iClip
	format(szString[iLen], iLen, szEnding)
}