#include <amxmodx>
#include <reapi>
#include <hns_matchsystem>
#include <hns_matchsystem_filter>
#include <hns_matchsystem_maps>

#define VOTEMAP_MENU_NAME "VoteMapListMenu"
#define VOTEMAP_CATEGORY_MENU_NAME "VoteMapCategoryMenu"
#define VOTEMAP_RESULT_MENU_NAME "VoteMapResultMenu"
#define VOTEMAP_TIE_MENU_NAME "VoteMapTieMenu"
#define VOTEMAP_MENU_SLOTS 6
#define VOTEMAP_MAX_SELECTED 5
#define VOTEMAP_CATEGORY_NONE 0
#define VOTEMAP_CATEGORY_BOOST 1
#define VOTEMAP_CATEGORY_SKILL 2
#define VOTEMAP_CATEGORY_NOMINATED 3
#define TASK_VOTEMAP_UPDATE 19401
#define VOTE_DURATION 10.0
#define VOTEMAP_DURATION 20.0

#define VOTEMAP_ADD_ACCESS_DENIED -2
#define VOTEMAP_ADD_LIMIT_REACHED -1
#define VOTEMAP_ADD_DUPLICATE 0
#define VOTEMAP_ADD_SUCCESS 1

const Float:VOTEMAP_UPDATE_INTERVAL = 0.5;

new bool:g_bVoteActive;
new g_iFirst, g_iSecond;
new g_szQuestion[64];
new g_szPrefix[24];
new g_iVoteMenu[MAX_PLAYERS + 1];
new g_iVoteModeMenu[MAX_PLAYERS + 1];
new g_iVoteMapMenu[MAX_PLAYERS + 1];

new Array:g_arrBoostMaps = Invalid_Array;
new Array:g_arrSkillMaps = Invalid_Array;
new Array:g_arrNominatedMaps = Invalid_Array;

new g_iVoteMapCategory[MAX_PLAYERS + 1];
new g_iVoteMapOffset[MAX_PLAYERS + 1];
new g_iVoteMapChoice[MAX_PLAYERS + 1][VOTEMAP_MENU_SLOTS];
new g_szVoteMapSelected[MAX_PLAYERS + 1][VOTEMAP_MAX_SELECTED][32];
new g_iVoteMapSelectedCount[MAX_PLAYERS + 1];

new g_szVoteMapOptions[VOTEMAP_MAX_SELECTED][32];
new g_iVoteMapOptionVotes[VOTEMAP_MAX_SELECTED];
new g_iVoteMapOptionCount;
new g_iVoteMapPlayerChoice[MAX_PLAYERS + 1];
new Float:g_flVoteMapEndTime;
new g_iVoteMapInitiator;
new g_szVoteMapWinner[32];
new g_szVoteMapTieOptions[VOTEMAP_MAX_SELECTED][32];
new g_iVoteMapTieCount;
new bool:g_bVoteMapTiePending;

public plugin_precache() {
	load_vote_maps();
}

public plugin_init() {
	register_plugin("HNS: Vote manager", "1.6", "OpenHNS");

	register_clcmd("say", "sayHandle");
	register_menucmd(register_menuid(VOTEMAP_MENU_NAME), 1023, "voteMapListMenuHandler");
	register_menucmd(register_menuid(VOTEMAP_CATEGORY_MENU_NAME), 1023, "voteMapCategoryMenuHandler");
	register_menucmd(register_menuid(VOTEMAP_RESULT_MENU_NAME), MENU_KEY_1 | MENU_KEY_2, "voteMapResultMenuHandler");
	register_menucmd(register_menuid(VOTEMAP_TIE_MENU_NAME), MENU_KEY_1 | MENU_KEY_2, "voteMapTieMenuHandler");

	for (new id = 1; id <= MaxClients; id++) {
		g_iVoteMapPlayerChoice[id] = -1;
	}
}

public plugin_natives() {
	register_library("hns_votemanager");
	register_native("hns_votemap_add_map", "native_votemap_add_map");
	set_native_filter("match_system_additons");
}

public native_votemap_add_map(amxx, params) {
	new id = get_param(1);
	if (!is_user_connected(id) || !isUserWatcher(id)) {
		return VOTEMAP_ADD_ACCESS_DENIED;
	}

	new szMap[32];
	get_string(2, szMap, charsmax(szMap));
	trim(szMap);

	new iResult = add_player_vote_map(id, szMap);
	switch (iResult) {
		case VOTEMAP_ADD_SUCCESS: {
			client_print_color(0, print_team_blue, "%s Player ^3%n^1 added ^3%s^1 to the voting list.", g_szPrefix, id, szMap);
		}
		case VOTEMAP_ADD_LIMIT_REACHED: {
			client_print_color(id, print_team_blue, "%s You can select up to ^3%d^1 maps.", g_szPrefix, VOTEMAP_MAX_SELECTED);
		}
		case VOTEMAP_ADD_DUPLICATE: {
			client_print_color(id, print_team_blue, "%s Map ^3%s^1 is already in your ^3/votemap^1 list.", g_szPrefix, szMap);
		}
	}

	return iResult;
}

public plugin_cfg() {
	hns_get_prefix(g_szPrefix, charsmax(g_szPrefix));
}

public plugin_end() {
	destroy_vote_maps();
}

public sayHandle(id) {
	new szArgs[128];
	read_args(szArgs, charsmax(szArgs));
	remove_quotes(szArgs);
	trim(szArgs);

	if(!szArgs[0])
		return PLUGIN_HANDLED;

	if(szArgs[0] != '/')
		return PLUGIN_CONTINUE;

	new szCmd[32], szParam[96];
	new pos = contain(szArgs, " ");

	if(pos != -1) {
		copy(szCmd, charsmax(szCmd), szArgs);
		szCmd[pos] = 0;
		copy(szParam, charsmax(szParam), szArgs[pos + 1]);
	} else {
		copy(szCmd, charsmax(szCmd), szArgs);
		szParam[0] = 0;
	}

	if(equali(szCmd, "/vote")) {
		if (!isUserWatcher(id)) {
			return PLUGIN_HANDLED;
		}

		if(g_bVoteActive) {
			client_print_color(id, print_team_blue, "%s Voting is already underway!", g_szPrefix);
			return PLUGIN_HANDLED;
		}

		if(strlen(szParam) < 2) {
			client_print_color(id, print_team_blue, "%s Usage: ^3/vote^1 <question>", g_szPrefix);
			return PLUGIN_HANDLED;
		}

		start_vote(id, szParam);
		return PLUGIN_HANDLED;
	}

	if(equali(szCmd, "/votemode")) {
		if (!isUserWatcher(id)) {
			return PLUGIN_HANDLED;
		}

		if(g_bVoteActive) {
			client_print_color(id, print_team_blue, "%s Voting is already underway!", g_szPrefix);
			return PLUGIN_HANDLED;
		}

		start_votemode(id);
		return PLUGIN_HANDLED;
	}

	if(equali(szCmd, "/votemap") || equali(szCmd, "/votemaps")) {
		if (!isUserWatcher(id)) {
			return PLUGIN_HANDLED;
		}

		if(g_bVoteActive) {
			client_print_color(id, print_team_blue, "%s Voting is already underway!", g_szPrefix);
			return PLUGIN_HANDLED;
		}

		refresh_nominated_maps();

		if (!ArraySize(g_arrBoostMaps) && !ArraySize(g_arrSkillMaps) && !ArraySize(g_arrNominatedMaps)) {
			client_print_color(id, print_team_blue, "%s No maps found in ^3hns-maps.ini^1.", g_szPrefix);
			return PLUGIN_HANDLED;
		}

		showVoteMapCategoryMenu(id);
		return PLUGIN_HANDLED;
	}

	return PLUGIN_CONTINUE;
}

public start_vote(id, szQuestion[]) {
	g_iFirst = 0;
	g_iSecond = 0;
	g_bVoteActive = true;

	copy(g_szQuestion, charsmax(g_szQuestion), szQuestion);

	client_print_color(0, print_team_blue, "%s ^3%n^1 started voting: ^3%s^1 (%.0f sec)", g_szPrefix, id, g_szQuestion, VOTE_DURATION);

	new iPlayers[MAX_PLAYERS], iNum;
	get_players(iPlayers, iNum, "ch");
	for(new i; i < iNum; ++i) {
		new id = iPlayers[i];
		voteMenu(id);
	}

	set_task(VOTE_DURATION, "end_vote");
}

public voteMenu(id) {
	closePlayerVoteMenus(id);

	new hMenu = menu_create(g_szQuestion, "voteMenuHandler");
	g_iVoteMenu[id] = hMenu;

	menu_additem(hMenu, "Yes.", "1");
	menu_additem(hMenu, "No.", "2");

	menu_setprop(hMenu, MPROP_PERPAGE, 0);
	menu_display(id, hMenu, 0);
}

public voteMenuHandler(id, hMenu, item) {
	if (g_iVoteMenu[id] != hMenu) {
		return PLUGIN_HANDLED;
	}

	g_iVoteMenu[id] = 0;

	if (item == MENU_EXIT) {
		menu_destroy(hMenu);
		return PLUGIN_HANDLED;
	}

	menu_destroy(hMenu);

	switch (item) {
		case 0: {
			g_iFirst++;
			client_print_color(0, print_team_blue, "%s Player ^3%n^1 voted: ^3Yes^1.", g_szPrefix, id);
		}
		case 1: {
			g_iSecond++;
			client_print_color(0, print_team_blue, "%s Player ^3%n^1 voted: ^3No^1.", g_szPrefix, id);
		}
	}
	return PLUGIN_HANDLED;
}

public end_vote() {
	g_bVoteActive = false;

	client_print_color(0, print_team_blue, "%s Voting results: ^3%s^1 - (Yes: ^3%d^1 | No: ^3%d^1)", g_szPrefix, g_szQuestion, g_iFirst, g_iSecond);

	new iPlayers[MAX_PLAYERS], iNum;
	get_players(iPlayers, iNum, "ch");
	for(new i; i < iNum; ++i) {
		new id = iPlayers[i];
		if (g_iVoteMenu[id]) {
			closeVoteMenu(id);
		}
	}

	g_iFirst = 0;
	g_iSecond = 0;
}

public start_votemode(id) {
	g_bVoteActive = true;
	g_iFirst = 0;
	g_iSecond = 0;

	client_print_color(0, print_team_blue, "%s ^3%n^1 started mode voting: ^3Boost^1 | ^3Skill^1 (10 sec)", g_szPrefix, id);

	new iPlayers[MAX_PLAYERS], iNum;
	get_players(iPlayers, iNum, "ch");
	for(new i; i < iNum; ++i) {
		new id = iPlayers[i];

		if (rg_get_user_team(id) == TEAM_SPECTATOR) {
			continue;
		}

		voteModeMenu(id);
	}

	set_task(10.0, "end_votemode");
}

public voteModeMenu(id) {
	closePlayerVoteMenus(id);

	new hMenu = menu_create("\rChoose a mode:", "voteModeMenuHandler");
	g_iVoteModeMenu[id] = hMenu;

	menu_additem(hMenu, "Boost.", "1");
	menu_additem(hMenu, "Skill.", "2");

	menu_setprop(hMenu, MPROP_PERPAGE, 0);
	menu_display(id, hMenu, 0);
}

public voteModeMenuHandler(id, hMenu, item) {
	if (g_iVoteModeMenu[id] != hMenu) {
		return PLUGIN_HANDLED;
	}

	g_iVoteModeMenu[id] = 0;

	if (item == MENU_EXIT) {
		menu_destroy(hMenu);
		return PLUGIN_HANDLED;
	}

	menu_destroy(hMenu);

	switch (item) {
		case 0: {
			g_iFirst++;
			client_print_color(0, print_team_blue, "%s Player ^3%n^1 voted: ^3Boost^1.", g_szPrefix, id);
		}
		case 1: {
			g_iSecond++;
			client_print_color(0, print_team_blue, "%s Player ^3%n^1 voted: ^3Skill^1.", g_szPrefix, id);
		}
	}
	return PLUGIN_HANDLED;
}

public end_votemode() {
	g_bVoteActive = false;

	if (g_iFirst > g_iSecond) {
		client_print_color(0, print_team_blue, "%s Voting results: ^3Boost^1 - (Boost: ^3%d^1 | Skill: ^3%d^1)", g_szPrefix, g_iFirst, g_iSecond);
	} else {
		client_print_color(0, print_team_blue, "%s Voting results: ^3Skill^1 - (Boost: ^3%d^1 | Skill: ^3%d^1)", g_szPrefix, g_iFirst, g_iSecond);
	}

	new iPlayers[MAX_PLAYERS], iNum;
	get_players(iPlayers, iNum, "ch");
	for(new i; i < iNum; ++i) {
		new id = iPlayers[i];
		if (g_iVoteModeMenu[id]) {
			closeVoteModeMenu(id);
		}
	}

	g_iFirst = 0;
	g_iSecond = 0;
}

public showVoteMapCategoryMenu(id) {
	if (!is_user_connected(id)) {
		return;
	}

	closePlayerVoteMenus(id);
	refresh_nominated_maps();

	new szMenu[768], iLen, iKeys;
	formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\rChoose a category:^n");
	iLen += strlen(szMenu[iLen]);

	if (g_iVoteMapSelectedCount[id] > 0) {
		formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\dSelected maps:^n");
		iLen += strlen(szMenu[iLen]);

		for (new i; i < g_iVoteMapSelectedCount[id]; i++) {
			formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\d%s^n", g_szVoteMapSelected[id][i]);
			iLen += strlen(szMenu[iLen]);
		}

	}

	formatex(szMenu[iLen], charsmax(szMenu) - iLen, "^n");
	iLen += strlen(szMenu[iLen]);

	if (ArraySize(g_arrBoostMaps)) {
		formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r1.\w Boost^n");
		iKeys |= MENU_KEY_1;
	} else {
		formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r1.\d Boost^n");
	}
	iLen += strlen(szMenu[iLen]);

	if (ArraySize(g_arrSkillMaps)) {
		formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r2.\w Skill^n");
		iKeys |= MENU_KEY_2;
	} else {
		formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r2.\d Skill^n");
	}
	iLen += strlen(szMenu[iLen]);

	if (ArraySize(g_arrNominatedMaps)) {
		formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r3.\w Nominated \y[%d]^n", ArraySize(g_arrNominatedMaps));
		iKeys |= MENU_KEY_3;
	} else {
		formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r3.\d Nominated [0]^n");
	}
	iLen += strlen(szMenu[iLen]);

	formatex(szMenu[iLen], charsmax(szMenu) - iLen, "^n");
	iLen += strlen(szMenu[iLen]);

	if (g_iVoteMapSelectedCount[id] >= 2) {
		formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r4.\w Start voting^n");
		iKeys |= MENU_KEY_4;
	} else {
		formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r4.\d Start voting^n");
	}
	iLen += strlen(szMenu[iLen]);

	if (g_iVoteMapSelectedCount[id] > 0) {
		formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r5. Clear selected maps^n");
		iKeys |= MENU_KEY_5;
	} else {
		formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r5.\d Clear selected maps^n");
	}
	iLen += strlen(szMenu[iLen]);

	formatex(szMenu[iLen], charsmax(szMenu) - iLen, "^n\r0.\w Exit");
	iKeys |= MENU_KEY_0;

	show_menu(id, iKeys, szMenu, -1, VOTEMAP_CATEGORY_MENU_NAME);
}

public voteMapCategoryMenuHandler(id, iKey) {
	if (!is_user_connected(id)) {
		return PLUGIN_HANDLED;
	}

	if (iKey == 9) {
		return PLUGIN_HANDLED;
	}

	new iCategory;
	switch (iKey) {
		case 0: iCategory = VOTEMAP_CATEGORY_BOOST;
		case 1: iCategory = VOTEMAP_CATEGORY_SKILL;
		case 2: iCategory = VOTEMAP_CATEGORY_NOMINATED;
		case 3: {
			if (g_iVoteMapSelectedCount[id] < 2) {
				client_print_color(id, print_team_blue, "%s Select at least ^32 maps^1 to start voting.", g_szPrefix);
				showVoteMapCategoryMenu(id);
				return PLUGIN_HANDLED;
			}

			start_vote_map(id);
			return PLUGIN_HANDLED;
		}
		case 4: {
			clear_player_vote_map_selection(id);
			showVoteMapCategoryMenu(id);
			return PLUGIN_HANDLED;
		}
		default: return PLUGIN_HANDLED;
	}

	new Array:arrMaps = get_vote_maps_array(iCategory);
	if (arrMaps == Invalid_Array || !ArraySize(arrMaps)) {
		client_print_color(id, print_team_blue, "%s No maps available in this category.", g_szPrefix);
		showVoteMapCategoryMenu(id);
		return PLUGIN_HANDLED;
	}

	g_iVoteMapCategory[id] = iCategory;
	g_iVoteMapOffset[id] = 0;

	showVoteMapListMenu(id);
	return PLUGIN_HANDLED;
}

showVoteMapListMenu(id) {
	if (!is_user_connected(id)) {
		return;
	}

	new Array:arrMaps = get_vote_maps_array(g_iVoteMapCategory[id]);
	if (arrMaps == Invalid_Array) {
		showVoteMapCategoryMenu(id);
		return;
	}

	new iTotal = ArraySize(arrMaps);
	if (!iTotal) {
		client_print_color(id, print_team_blue, "%s No maps available in this category.", g_szPrefix);
		showVoteMapCategoryMenu(id);
		return;
	}

	new iOffset = g_iVoteMapOffset[id];
	if (iOffset >= iTotal) {
		iOffset = 0;
		g_iVoteMapOffset[id] = 0;
	}

	new iCurrentPage = (iOffset / VOTEMAP_MENU_SLOTS) + 1;
	new iTotalPages = (iTotal + VOTEMAP_MENU_SLOTS - 1) / VOTEMAP_MENU_SLOTS;
	new szCategory[16];
	get_vote_map_category_name(g_iVoteMapCategory[id], szCategory, charsmax(szCategory));

	new szMenu[512], iLen, iKeys;
	formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\rMap selection \y%d/%d^n", iCurrentPage, iTotalPages);
	iLen += strlen(szMenu[iLen]);

	formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\dCategory: %s^n", szCategory);
	iLen += strlen(szMenu[iLen]);

	formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\dSelected: %d/%d^n^n", g_iVoteMapSelectedCount[id], VOTEMAP_MAX_SELECTED);
	iLen += strlen(szMenu[iLen]);

	for (new i; i < VOTEMAP_MENU_SLOTS; i++) {
		g_iVoteMapChoice[id][i] = -1;
	}

	new iShown;
	for (new i; i < VOTEMAP_MENU_SLOTS && (iOffset + i) < iTotal; i++) {
		new szMap[32];
		ArrayGetString(arrMaps, iOffset + i, szMap, charsmax(szMap));

		if (is_player_vote_map_selected(id, szMap) != -1) {
			formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r%d.\w %s \y[*]^n", i + 1, szMap);
		} else {
			formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r%d.\w %s^n", i + 1, szMap);
		}
		iLen += strlen(szMenu[iLen]);

		g_iVoteMapChoice[id][i] = iOffset + i;
		iKeys |= (1 << i);
		iShown++;
	}

	formatex(szMenu[iLen], charsmax(szMenu) - iLen, "^n\r7.\w Start voting^n^n");
	iLen += strlen(szMenu[iLen]);
	iKeys |= MENU_KEY_7;

	if (iCurrentPage > 1) {
		formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r8.\w Previous page^n");
	} else {
		formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r8.\w Categories^n");
	}
	iLen += strlen(szMenu[iLen]);
	iKeys |= MENU_KEY_8;

	if (iOffset + iShown < iTotal) {
		formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r9.\w Next page^n");
		iKeys |= MENU_KEY_9;
	} else {
		formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r9.\d Next page^n");
	}
	iLen += strlen(szMenu[iLen]);

	formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\r0.\w Exit");
	iKeys |= MENU_KEY_0;

	show_menu(id, iKeys, szMenu, -1, VOTEMAP_MENU_NAME);
}

public voteMapListMenuHandler(id, iKey) {
	if (!is_user_connected(id)) {
		return PLUGIN_HANDLED;
	}

	new Array:arrMaps = get_vote_maps_array(g_iVoteMapCategory[id]);
	if (arrMaps == Invalid_Array) {
		return PLUGIN_HANDLED;
	}

	new iTotal = ArraySize(arrMaps);
	switch (iKey) {
		case 0 .. (VOTEMAP_MENU_SLOTS - 1): {
			new iMapIndex = g_iVoteMapChoice[id][iKey];
			if (iMapIndex < 0 || iMapIndex >= iTotal) {
				showVoteMapListMenu(id);
				return PLUGIN_HANDLED;
			}

			new szMap[32];
			ArrayGetString(arrMaps, iMapIndex, szMap, charsmax(szMap));
			toggle_player_vote_map(id, szMap);
			showVoteMapListMenu(id);
		}
		case 6: {
			start_vote_map(id);
		}
		case 7: {
			if (g_iVoteMapOffset[id] >= VOTEMAP_MENU_SLOTS) {
				g_iVoteMapOffset[id] -= VOTEMAP_MENU_SLOTS;
				showVoteMapListMenu(id);
			} else {
				showVoteMapCategoryMenu(id);
			}
		}
		case 8: {
			if (g_iVoteMapOffset[id] + VOTEMAP_MENU_SLOTS < iTotal) {
				g_iVoteMapOffset[id] += VOTEMAP_MENU_SLOTS;
				showVoteMapListMenu(id);
			}
		}
		case 9: {
			g_iVoteMapCategory[id] = VOTEMAP_CATEGORY_NONE;
			g_iVoteMapOffset[id] = 0;
		}
	}

	return PLUGIN_HANDLED;
}

public start_vote_map(id) {
	if (g_bVoteActive) {
		client_print_color(id, print_team_blue, "%s Voting is already underway!", g_szPrefix);
		return;
	}

	if (g_iVoteMapSelectedCount[id] < 2) {
		client_print_color(id, print_team_blue, "%s Select at least ^32 maps^1 to start voting.", g_szPrefix);
		showVoteMapListMenu(id);
		return;
	}

	g_iVoteMapOptionCount = g_iVoteMapSelectedCount[id];

	for (new i; i < g_iVoteMapOptionCount; i++) {
		copy(g_szVoteMapOptions[i], charsmax(g_szVoteMapOptions[]), g_szVoteMapSelected[id][i]);
	}

	g_iVoteMapTieCount = 0;
	g_bVoteMapTiePending = false;
	begin_vote_map_round(id, false);
	reset_player_vote_map_state(id);
}

begin_vote_map_round(id, bool:bRestart) {
	g_bVoteActive = true;
	g_iVoteMapInitiator = id;
	g_szVoteMapWinner[0] = EOS;

	for (new i; i < g_iVoteMapOptionCount; i++) {
		g_iVoteMapOptionVotes[i] = 0;
	}

	for (new iPlayer = 1; iPlayer <= MaxClients; iPlayer++) {
		g_iVoteMapPlayerChoice[iPlayer] = -1;
	}

	g_flVoteMapEndTime = get_gametime() + VOTEMAP_DURATION;

	show_menu(id, 0, "", 1);
	if (bRestart) {
		client_print_color(0, print_team_blue, "%s ^3%n^1 restarted voting between tied maps! (%.0f sec)", g_szPrefix, id, VOTEMAP_DURATION);
	} else {
		client_print_color(0, print_team_blue, "%s ^3%n^1 started map voting! (%.0f sec)", g_szPrefix, id, VOTEMAP_DURATION);
	}

	new iPlayers[MAX_PLAYERS], iNum;
	get_players(iPlayers, iNum, "ch");
	for (new i; i < iNum; i++) {
		new iPlayer = iPlayers[i];
		if (rg_get_user_team(iPlayer) == TEAM_SPECTATOR) {
			continue;
		}

		closePlayerVoteMenus(iPlayer);
		voteMapMenu(iPlayer);
	}

	remove_task(TASK_VOTEMAP_UPDATE);
	set_task(VOTEMAP_UPDATE_INTERVAL, "taskUpdateVoteMapMenus", TASK_VOTEMAP_UPDATE, .flags = "b");
	set_task(VOTEMAP_DURATION, "end_vote_map");
}

public voteMapMenu(id) {
	if (!g_bVoteActive || g_iVoteMapOptionCount <= 0 || !is_user_connected(id) || rg_get_user_team(id) == TEAM_SPECTATOR) {
		return;
	}

	destroyVoteMapMenu(id);

	new Float:flTimeLeft = floatmax(0.0, g_flVoteMapEndTime - get_gametime());
	new szTitle[96];
	formatex(szTitle, charsmax(szTitle), "\rChoose a map:^n\dTime left: \y%.1f sec.", flTimeLeft);

	new hMenu = menu_create(szTitle, "voteMapMenuHandler");
	g_iVoteMapMenu[id] = hMenu;

	for (new i; i < g_iVoteMapOptionCount; i++) {
		new szItem[64];

		if (g_iVoteMapPlayerChoice[id] == i) {
			formatex(szItem, charsmax(szItem), "\d%s [%d]", g_szVoteMapOptions[i], g_iVoteMapOptionVotes[i]);
		} else {
			formatex(szItem, charsmax(szItem), "%s \y[%d]", g_szVoteMapOptions[i], g_iVoteMapOptionVotes[i]);
		}

		menu_additem(hMenu, szItem);
	}

	menu_setprop(hMenu, MPROP_PERPAGE, 0);
	menu_setprop(hMenu, MPROP_EXIT, MEXIT_NEVER);
	menu_display(id, hMenu, 0);
}

public taskUpdateVoteMapMenus() {
	if (!g_bVoteActive || g_iVoteMapOptionCount <= 0 || get_gametime() >= g_flVoteMapEndTime) {
		remove_task(TASK_VOTEMAP_UPDATE);
		return;
	}

	new iPlayers[MAX_PLAYERS], iNum;
	get_players(iPlayers, iNum, "ch");

	for (new i; i < iNum; i++) {
		new id = iPlayers[i];

		if (rg_get_user_team(id) == TEAM_SPECTATOR) {
			closeVoteMapMenu(id);
			continue;
		}

		voteMapMenu(id);
	}
}

public voteMapMenuHandler(id, hMenu, item) {
	if (g_iVoteMapMenu[id] != hMenu) {
		return PLUGIN_HANDLED;
	}

	g_iVoteMapMenu[id] = 0;
	menu_destroy(hMenu);

	if (!g_bVoteActive || g_iVoteMapOptionCount <= 0) {
		return PLUGIN_HANDLED;
	}

	if (item < 0 || item >= g_iVoteMapOptionCount) {
		voteMapMenu(id);
		return PLUGIN_HANDLED;
	}

	new iOldChoice = g_iVoteMapPlayerChoice[id];
	if (iOldChoice != item) {
		if (iOldChoice >= 0 && iOldChoice < g_iVoteMapOptionCount && g_iVoteMapOptionVotes[iOldChoice] > 0) {
			g_iVoteMapOptionVotes[iOldChoice]--;
		}

		g_iVoteMapPlayerChoice[id] = item;
		g_iVoteMapOptionVotes[item]++;
	}

	voteMapMenu(id);
	return PLUGIN_HANDLED;
}

public end_vote_map() {
	remove_task(TASK_VOTEMAP_UPDATE);
	g_flVoteMapEndTime = 0.0;
	g_bVoteActive = false;
	g_bVoteMapTiePending = false;
	g_iVoteMapTieCount = 0;

	new iBestVotes = -1;
	new iBestCount;
	new iBestIndexes[VOTEMAP_MAX_SELECTED];

	for (new i; i < g_iVoteMapOptionCount; i++) {
		if (g_iVoteMapOptionVotes[i] > iBestVotes) {
			iBestVotes = g_iVoteMapOptionVotes[i];
			iBestIndexes[0] = i;
			iBestCount = 1;
		} else if (g_iVoteMapOptionVotes[i] == iBestVotes) {
			iBestIndexes[iBestCount++] = i;
		}
	}

	if (iBestVotes <= 0) {
		client_print_color(0, print_team_blue, "%s No votes received.", g_szPrefix);
	} else if (iBestCount == 1) {
		client_print_color(0, print_team_blue, "%s Winning map: ^3%s^1 - ^3%d^1 vote(s).", g_szPrefix, g_szVoteMapOptions[iBestIndexes[0]], iBestVotes);
		copy(g_szVoteMapWinner, charsmax(g_szVoteMapWinner), g_szVoteMapOptions[iBestIndexes[0]]);
	} else {
		new szTiedMaps[192];
		for (new i; i < iBestCount; i++) {
			copy(g_szVoteMapTieOptions[i], charsmax(g_szVoteMapTieOptions[]), g_szVoteMapOptions[iBestIndexes[i]]);

			if (i) {
				add(szTiedMaps, charsmax(szTiedMaps), ", ");
			}
			add(szTiedMaps, charsmax(szTiedMaps), g_szVoteMapOptions[iBestIndexes[i]]);
		}

		client_print_color(0, print_team_blue, "%s Draw between: ^3%s^1.", g_szPrefix, szTiedMaps);
		g_iVoteMapTieCount = iBestCount;
	}

	new iPlayers[MAX_PLAYERS], iNum;
	get_players(iPlayers, iNum, "ch");
	for (new i; i < iNum; ++i) {
		new id = iPlayers[i];
		if (g_iVoteMapMenu[id]) {
			closeVoteMapMenu(id);
		}
	}

	g_iVoteMapOptionCount = 0;

	for (new id = 1; id <= MaxClients; id++) {
		g_iVoteMapPlayerChoice[id] = -1;
	}

	if (g_szVoteMapWinner[0] && is_user_connected(g_iVoteMapInitiator)) {
		showVoteMapResultMenu(g_iVoteMapInitiator);
	} else if (g_iVoteMapTieCount >= 2 && is_user_connected(g_iVoteMapInitiator)) {
		g_bVoteMapTiePending = true;
		g_bVoteActive = true;
		showVoteMapTieMenu(g_iVoteMapInitiator);
	} else {
		g_iVoteMapInitiator = 0;
		g_szVoteMapWinner[0] = EOS;
		g_iVoteMapTieCount = 0;
	}
}

showVoteMapTieMenu(id) {
	new szMenu[384], iLen;
	iLen = formatex(szMenu, charsmax(szMenu), "\rDraw between maps:^n");

	for (new i; i < g_iVoteMapTieCount; i++) {
		iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y%s^n", g_szVoteMapTieOptions[i]);
	}

	formatex(szMenu[iLen], charsmax(szMenu) - iLen,
		"^n\wRestart voting with these maps?^n^n\r1.\w Yes^n\r2.\w No");

	show_menu(id, MENU_KEY_1 | MENU_KEY_2, szMenu, -1, VOTEMAP_TIE_MENU_NAME);
}

public voteMapTieMenuHandler(id, iKey) {
	if (id != g_iVoteMapInitiator || !g_bVoteMapTiePending || g_iVoteMapTieCount < 2) {
		return PLUGIN_HANDLED;
	}

	g_bVoteMapTiePending = false;
	g_bVoteActive = false;

	if (iKey == 0) {
		g_iVoteMapOptionCount = g_iVoteMapTieCount;
		for (new i; i < g_iVoteMapOptionCount; i++) {
			copy(g_szVoteMapOptions[i], charsmax(g_szVoteMapOptions[]), g_szVoteMapTieOptions[i]);
		}

		g_iVoteMapTieCount = 0;
		begin_vote_map_round(id, true);
	} else {
		g_iVoteMapInitiator = 0;
		g_iVoteMapTieCount = 0;
	}

	return PLUGIN_HANDLED;
}

showVoteMapResultMenu(id) {
	new szMenu[256];
	formatex(szMenu, charsmax(szMenu), "\rMap \y%s \rwon the vote.^n\wDo you want to change to it?^n^n\r1.\w Yes^n\r2.\w No", g_szVoteMapWinner);
	show_menu(id, MENU_KEY_1 | MENU_KEY_2, szMenu, -1, VOTEMAP_RESULT_MENU_NAME);
}

public voteMapResultMenuHandler(id, iKey) {
	if (id != g_iVoteMapInitiator || !g_szVoteMapWinner[0]) {
		return PLUGIN_HANDLED;
	}

	new szWinner[32];
	copy(szWinner, charsmax(szWinner), g_szVoteMapWinner);

	g_iVoteMapInitiator = 0;
	g_szVoteMapWinner[0] = EOS;

	if (iKey == 0) {
		engine_changelevel(szWinner);
	}

	return PLUGIN_HANDLED;
}

stock closeVoteMapMenu(id) {
	new hMenu = g_iVoteMapMenu[id];
	g_iVoteMapMenu[id] = 0;

	if (is_user_connected(id)) {
		menu_cancel(id);
		show_menu(id, 0, "", 1);
	}

	if (hMenu) {
		menu_destroy(hMenu);
	}
}

stock destroyVoteMapMenu(id) {
	new hMenu = g_iVoteMapMenu[id];
	g_iVoteMapMenu[id] = 0;

	if (hMenu) {
		menu_destroy(hMenu);
	}
}

stock closeVoteMenu(id) {
	new hMenu = g_iVoteMenu[id];
	g_iVoteMenu[id] = 0;

	if (is_user_connected(id)) {
		menu_cancel(id);
		show_menu(id, 0, "", 1);
	}

	if (hMenu) {
		menu_destroy(hMenu);
	}
}

stock closeVoteModeMenu(id) {
	new hMenu = g_iVoteModeMenu[id];
	g_iVoteModeMenu[id] = 0;

	if (is_user_connected(id)) {
		menu_cancel(id);
		show_menu(id, 0, "", 1);
	}

	if (hMenu) {
		menu_destroy(hMenu);
	}
}

stock closePlayerVoteMenus(id) {
	new hVoteMenu = g_iVoteMenu[id];
	new hVoteModeMenu = g_iVoteModeMenu[id];
	new hVoteMapMenu = g_iVoteMapMenu[id];

	g_iVoteMenu[id] = 0;
	g_iVoteModeMenu[id] = 0;
	g_iVoteMapMenu[id] = 0;

	if (is_user_connected(id)) {
		menu_cancel(id);
		show_menu(id, 0, "", 1);
	}

	if (hVoteMenu) {
		menu_destroy(hVoteMenu);
	}

	if (hVoteModeMenu) {
		menu_destroy(hVoteModeMenu);
	}

	if (hVoteMapMenu) {
		menu_destroy(hVoteMapMenu);
	}
}

stock destroyPlayerVoteMenus(id) {
	new hVoteMenu = g_iVoteMenu[id];
	new hVoteModeMenu = g_iVoteModeMenu[id];
	new hVoteMapMenu = g_iVoteMapMenu[id];

	g_iVoteMenu[id] = 0;
	g_iVoteModeMenu[id] = 0;
	g_iVoteMapMenu[id] = 0;

	if (hVoteMenu) {
		menu_destroy(hVoteMenu);
	}

	if (hVoteModeMenu) {
		menu_destroy(hVoteModeMenu);
	}

	if (hVoteMapMenu) {
		menu_destroy(hVoteMapMenu);
	}
}

Array:get_vote_maps_array(iCategory) {
	switch (iCategory) {
		case VOTEMAP_CATEGORY_BOOST: return g_arrBoostMaps;
		case VOTEMAP_CATEGORY_SKILL: return g_arrSkillMaps;
		case VOTEMAP_CATEGORY_NOMINATED: return g_arrNominatedMaps;
	}

	return Invalid_Array;
}

get_vote_map_category_name(iCategory, szBuffer[], iLen) {
	switch (iCategory) {
		case VOTEMAP_CATEGORY_BOOST: copy(szBuffer, iLen, "Boost");
		case VOTEMAP_CATEGORY_SKILL: copy(szBuffer, iLen, "Skill");
		case VOTEMAP_CATEGORY_NOMINATED: copy(szBuffer, iLen, "Nominated");
		default: copy(szBuffer, iLen, "Unknown");
	}
}

refresh_nominated_maps() {
	if (g_arrNominatedMaps == Invalid_Array) {
		return;
	}

	ArrayClear(g_arrNominatedMaps);

	new iCount = hnsmatch_maps_get_nominated_count();
	for (new i; i < iCount; i++) {
		new szMap[32];
		if (hnsmatch_maps_get_nominated(i, szMap, charsmax(szMap)) && szMap[0]) {
			ArrayPushString(g_arrNominatedMaps, szMap);
		}
	}
}

is_player_vote_map_selected(id, const szMap[]) {
	for (new i; i < g_iVoteMapSelectedCount[id]; i++) {
		if (equali(g_szVoteMapSelected[id][i], szMap)) {
			return i;
		}
	}

	return -1;
}

toggle_player_vote_map(id, const szMap[]) {
	new iSelected = is_player_vote_map_selected(id, szMap);
	if (iSelected != -1) {
		for (new i = iSelected; i < g_iVoteMapSelectedCount[id] - 1; i++) {
			copy(g_szVoteMapSelected[id][i], charsmax(g_szVoteMapSelected[][]), g_szVoteMapSelected[id][i + 1]);
		}

		g_iVoteMapSelectedCount[id]--;
		g_szVoteMapSelected[id][g_iVoteMapSelectedCount[id]][0] = EOS;
		return;
	}

	if (add_player_vote_map(id, szMap) == VOTEMAP_ADD_LIMIT_REACHED) {
		client_print_color(id, print_team_blue, "%s You can select up to ^3%d^1 maps.", g_szPrefix, VOTEMAP_MAX_SELECTED);
	}
}

add_player_vote_map(id, const szMap[]) {
	if (!szMap[0]) {
		return VOTEMAP_ADD_DUPLICATE;
	}

	if (is_player_vote_map_selected(id, szMap) != -1) {
		return VOTEMAP_ADD_DUPLICATE;
	}

	if (g_iVoteMapSelectedCount[id] >= VOTEMAP_MAX_SELECTED) {
		return VOTEMAP_ADD_LIMIT_REACHED;
	}

	copy(g_szVoteMapSelected[id][g_iVoteMapSelectedCount[id]], charsmax(g_szVoteMapSelected[][]), szMap);
	g_iVoteMapSelectedCount[id]++;

	return VOTEMAP_ADD_SUCCESS;
}

clear_player_vote_map_selection(id) {
	for (new i; i < VOTEMAP_MAX_SELECTED; i++) {
		g_szVoteMapSelected[id][i][0] = EOS;
	}

	g_iVoteMapSelectedCount[id] = 0;
}

reset_player_vote_map_state(id) {
	clear_player_vote_map_selection(id);
	g_iVoteMapCategory[id] = VOTEMAP_CATEGORY_NONE;
	g_iVoteMapOffset[id] = 0;

	for (new i; i < VOTEMAP_MENU_SLOTS; i++) {
		g_iVoteMapChoice[id][i] = -1;
	}
}

load_vote_maps() {
	destroy_vote_maps();

	g_arrBoostMaps = ArrayCreate(32);
	g_arrSkillMaps = ArrayCreate(32);
	g_arrNominatedMaps = ArrayCreate(32);

	new szPath[128], szFile[160];
	get_localinfo("amxx_configsdir", szPath, charsmax(szPath));
	formatex(szFile, charsmax(szFile), "%s/mixsystem/hns-maps.ini", szPath);

	new fp = fopen(szFile, "rt");
	if (!fp) {
		log_amx("Couldn't open %s", szFile);
		return;
	}

	new szLine[128], szMap[32], iCategory = VOTEMAP_CATEGORY_NONE;
	while (!feof(fp)) {
		fgets(fp, szLine, charsmax(szLine));
		trim(szLine);

		if (!szLine[0] || szLine[0] == ';') {
			continue;
		}

		if (szLine[0] == '[') {
			iCategory = parse_vote_map_category(szLine);
			continue;
		}

		if (iCategory == VOTEMAP_CATEGORY_NONE) {
			continue;
		}

		parse(szLine, szMap, charsmax(szMap));
		if (!szMap[0]) {
			continue;
		}

		switch (iCategory) {
			case VOTEMAP_CATEGORY_BOOST: ArrayPushString(g_arrBoostMaps, szMap);
			case VOTEMAP_CATEGORY_SKILL: ArrayPushString(g_arrSkillMaps, szMap);
		}
	}

	fclose(fp);
}

parse_vote_map_category(const szLine[]) {
	new szSection[32], iPos;
	for (new i = 1; szLine[i] && szLine[i] != ']' && iPos < charsmax(szSection); i++) {
		szSection[iPos++] = szLine[i];
	}
	szSection[iPos] = EOS;
	strtolower(szSection);

	if (equali(szSection, "boost")) {
		return VOTEMAP_CATEGORY_BOOST;
	}

	if (equali(szSection, "skill")) {
		return VOTEMAP_CATEGORY_SKILL;
	}

	return VOTEMAP_CATEGORY_NONE;
}

destroy_vote_maps() {
	if (g_arrBoostMaps != Invalid_Array) {
		ArrayDestroy(g_arrBoostMaps);
		g_arrBoostMaps = Invalid_Array;
	}

	if (g_arrSkillMaps != Invalid_Array) {
		ArrayDestroy(g_arrSkillMaps);
		g_arrSkillMaps = Invalid_Array;
	}

	if (g_arrNominatedMaps != Invalid_Array) {
		ArrayDestroy(g_arrNominatedMaps);
		g_arrNominatedMaps = Invalid_Array;
	}
}

public client_connect(id) {
	destroyPlayerVoteMenus(id);
	g_iVoteMapPlayerChoice[id] = -1;
	reset_player_vote_map_state(id);
}

public client_disconnected(id) {
	new iChoice = g_iVoteMapPlayerChoice[id];
	if (g_bVoteActive && iChoice >= 0 && iChoice < g_iVoteMapOptionCount && g_iVoteMapOptionVotes[iChoice] > 0) {
		g_iVoteMapOptionVotes[iChoice]--;
	}

	if (id == g_iVoteMapInitiator && g_bVoteMapTiePending) {
		g_bVoteMapTiePending = false;
		g_bVoteActive = false;
		g_iVoteMapTieCount = 0;
		g_iVoteMapInitiator = 0;
	} else if (id == g_iVoteMapInitiator && g_szVoteMapWinner[0]) {
		g_szVoteMapWinner[0] = EOS;
		g_iVoteMapInitiator = 0;
	}

	destroyPlayerVoteMenus(id);
	g_iVoteMapPlayerChoice[id] = -1;
	reset_player_vote_map_state(id);
}
