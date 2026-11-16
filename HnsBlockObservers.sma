#include <amxmodx>
#include <reapi>
#include <hns_matchsystem>

#define TASK_CHECK 31027

#define OBS_BYPASS_FLAG ADMIN_BAN

new bool:g_bBlockTTSpectate;

new bool:g_bFindNextReverse;
new g_iFindNextStart;

new g_szPrefix[24];

public plugin_cfg() {
	hns_get_prefix(g_szPrefix, charsmax(g_szPrefix));
}

public plugin_init() {
	register_plugin("HNS: Block observers Boost", "1.3", "OpenHNS"); // Garey

	// Блокировки наблюдения
	RegisterHookChain(RG_CBasePlayer_Observer_FindNextPlayer, "CBasePlayer_Observer_FindNextPlayer_Pre", false);
	RegisterHookChain(RG_CBasePlayer_Observer_IsValidTarget, "CBasePlayer_Observer_IsValidTarget_Pre", false);
	RegisterHookChain(RG_CBasePlayer_Observer_SetMode, "CBasePlayer_Observer_SetMode_Pre", false);
	RegisterHookChain(RG_CBasePlayer_PreThink, "CBasePlayer_PreThink");

	// Чекеры для блокировок наблюдения
	RegisterHookChain(RG_CSGameRules_RestartRound, "CSGameRules_RestartRound_Post", true);

	RegisterHookChain(RG_CBasePlayer_Killed, "CBasePlayer_Killed_Post", true);
}

// Подготовка для find_allowed_player
public CBasePlayer_Observer_FindNextPlayer_Pre(const this, bool:reverse, name[]) {
	new observerTarget = get_entvar(this, var_iuser2);

	g_bFindNextReverse = reverse;
	g_iFindNextStart = is_user_alive(observerTarget) ? observerTarget : this;
}

// Нужно ли запрещать текущую цель и подменяем её
public CBasePlayer_Observer_IsValidTarget_Pre(this, player, bool:same_team) {
	if (!g_bBlockTTSpectate) {
		return;
	}

	if (!is_user_connected(this) || !is_user_connected(player)) {
		return;
	}

	if (rg_get_user_team(player) != TEAM_TERRORIST) {
		return;
	}

	// TT players can continue spectating TT.
	if (rg_get_user_team(this) == TEAM_TERRORIST) {
		return;
	}

	if (has_observer_bypass(this)) {
		return;
	}

	SetHookChainArg(2, ATYPE_INTEGER, find_allowed_player(player));
}

public CBasePlayer_Observer_SetMode_Pre(this, iMode) {
	if (!is_observer_restrictions_active(this)) {
		return;
	}

	if (!is_free_fly_mode(iMode)) {
		return;
	}

	SetHookChainArg(2, ATYPE_INTEGER, OBS_CHASE_FREE);
}

// Подбираем допустимую цель для подмены.
find_allowed_player(current) {
	new start = g_iFindNextStart;
	new dir = g_bFindNextReverse ? -1 : 1;

	if (start < 1 || start > MaxClients) {
		start = current;
	}

	if (current < 1 || current > MaxClients) {
		current = start;
	}

	do {
		current += dir;

		if (current > MaxClients) {
			current = 1;
		} else if (current < 1) {
			current = MaxClients;
		}

		if (!is_user_alive(current)) {
			continue;
		}

		if (rg_get_user_team(current) == TEAM_TERRORIST) {
			continue;
		}

		return current;
	} while (current != start);

	return -1;
}

public CBasePlayer_PreThink(id) {
	if (!g_bBlockTTSpectate) {
		return HC_CONTINUE;
	}

	if (!is_user_connected(id) || is_user_alive(id)) {
		return HC_CONTINUE;
	}

	if (rg_get_user_team(id) == TEAM_TERRORIST) {
		return HC_CONTINUE;
	}

	if (has_observer_bypass(id)) {
		return HC_CONTINUE;
	}

	if (is_observing_tt(id)) {
		switch_observer_to_ct(id);
	}

	enforce_observer_mode(id);

	return HC_CONTINUE;
}


public TaskBlockCheker() {
	if (!is_mix_started()) {
		g_bBlockTTSpectate = false;
		remove_task(TASK_CHECK);
		return;
	}

	check_block();
}

public client_disconnected(id) {
	check_block();
}

public CSGameRules_RestartRound_Post() {
	g_bBlockTTSpectate = false;
	
	if (task_exists(TASK_CHECK)) {
		remove_task(TASK_CHECK);
	}

	if (is_mix_started()) {
		set_task(1.0, "TaskBlockCheker", TASK_CHECK, .flags = "b");
	}
}

public CBasePlayer_Killed_Post(victim, attacker) {
	check_block();
}

stock bool:has_observer_bypass(id) {
	return bool:(get_user_flags(id) & OBS_BYPASS_FLAG);
}

stock switch_observer_to_ct(id) {
	new iCT = get_first_alive_ct();
	if (!iCT) {
		return;
	}

	set_member(id, m_hObserverTarget, iCT);
	set_entvar(id, var_iuser2, iCT);

	new iMode = get_entvar(id, var_iuser1);
	if (iMode != OBS_CHASE_LOCKED && iMode != OBS_CHASE_FREE && iMode != OBS_IN_EYE) {
		rg_set_observer_mode(id, OBS_CHASE_FREE);
	}
}

stock enforce_observer_mode(id) {
	new iMode = get_entvar(id, var_iuser1);
	if (!is_free_fly_mode(iMode)) {
		return;
	}

	new iCT = get_first_alive_ct();
	if (iCT) {
		set_member(id, m_hObserverTarget, iCT);
		set_entvar(id, var_iuser2, iCT);
	}

	rg_set_observer_mode(id, OBS_CHASE_FREE);
}

stock get_first_alive_ct() {
	new iPlayers[MAX_PLAYERS], iNum;
	get_players(iPlayers, iNum, "aceh", "CT");
	return (iNum > 0) ? iPlayers[0] : 0;
}

stock check_block() {
	if (!is_mix_started()) {
		g_bBlockTTSpectate = false;
		return;
	}

	new iTotalTT = get_total_tt_count();
	new iAliveTT = get_alive_tt_count();

	new bool:bShouldBlock;
	new iBlockOnAlive = 2;

	if (iTotalTT == 3) {
		iBlockOnAlive = 1;
		bShouldBlock = iAliveTT <= 1;
	} else if (iTotalTT > 3) {
		iBlockOnAlive = 2;
		bShouldBlock = iAliveTT <= 2;
	} else {
		bShouldBlock = false;
	}

	if (bShouldBlock == g_bBlockTTSpectate) {
		return;
	}

	g_bBlockTTSpectate = bShouldBlock;

	if (!g_bBlockTTSpectate) {
		return;
	}
	
	client_print_color(0, print_team_blue, "%s Осталось^3 %d TT^1, наблюдение за ^3TT^1 отключено для наблюдателей.", g_szPrefix, iBlockOnAlive);

	new iPlayers[MAX_PLAYERS], iNum;
	get_players(iPlayers, iNum, "che", "SPECTATOR");

	for (new i; i < iNum; i++) {
		new id = iPlayers[i];

		if (!is_user_connected(id) || is_user_alive(id)) {
			continue;
		}

		if (has_observer_bypass(id)) {
			continue;
		}

		if (!is_observing_tt(id)) {
			enforce_observer_mode(id);
			continue;
		}

		switch_observer_to_ct(id);
		enforce_observer_mode(id);
	}
}

stock get_alive_tt_count() {
	new iPlayers[MAX_PLAYERS], iNum;
	get_players(iPlayers, iNum, "aceh", "TERRORIST");
	return iNum;
}

stock get_total_tt_count() {
	new iPlayers[MAX_PLAYERS], iNum;
	get_players(iPlayers, iNum, "ceh", "TERRORIST");
	return iNum;
}

stock bool:is_observing_tt(id) {
	new iTarget = get_member(id, m_hObserverTarget);
	if (!is_user_alive(iTarget)) {
		return false;
	}

	return rg_get_user_team(iTarget) == TEAM_TERRORIST;
}

stock bool:is_observer_restrictions_active(id) {
	if (!g_bBlockTTSpectate) {
		return false;
	}

	if (!is_user_connected(id) || is_user_alive(id)) {
		return false;
	}

	if (rg_get_user_team(id) == TEAM_TERRORIST) {
		return false;
	}

	if (has_observer_bypass(id)) {
		return false;
	}

	return true;
}

stock bool:is_free_fly_mode(iMode) {
	return iMode == OBS_ROAMING || iMode == OBS_MAP_FREE || iMode == OBS_MAP_CHASE;
}

stock bool:is_mix_started() {
	return hns_get_mode() == MODE_MIX && hns_get_status() == MATCH_STARTED && hns_isboost();
}