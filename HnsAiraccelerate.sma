#include <amxmodx>
#include <hns_matchsystem>

const AIRACCELERATE_LOW = 10;
const AIRACCELERATE_HIGH = 100;

new g_szPrefix[24];
new g_pAiraccelerate;

public plugin_init() {
	register_plugin("HNS: Airaccelerate chooser", "1.0", "OpenHNS");

	RegisterSayCmd("100aa", "aa100", "cmd100aa", hns_get_flag_watcher(), "Choose 100 airaccelerate");
	RegisterSayCmd("10aa", "aa10", "cmd10aa", hns_get_flag_watcher(), "Choose 10 airaccelerate");

	g_pAiraccelerate = get_cvar_pointer("sv_airaccelerate");
}

public plugin_cfg() {
	hns_get_prefix(g_szPrefix, charsmax(g_szPrefix));
}

public cmd100aa(id) {
	if (!isUserWatcher(id)) {
		return PLUGIN_HANDLED;
	}

	set_airaccelerate(id, AIRACCELERATE_HIGH);
	return PLUGIN_HANDLED;
}

public cmd10aa(id) {
	if (!isUserWatcher(id)) {
		return PLUGIN_HANDLED;
	}

	set_airaccelerate(id, AIRACCELERATE_LOW);
	return PLUGIN_HANDLED;
}

stock set_airaccelerate(id, value) {
	if (hns_get_mode() == MODE_MIX) {
		client_print_color(id, print_team_blue, "%s Команда недоступна во время ^3Match^1.", g_szPrefix);
		return;
	}

	if (g_pAiraccelerate) {
		set_pcvar_num(g_pAiraccelerate, value);
	} else {
		set_cvar_num("sv_airaccelerate", value);
	}

	client_print_color(0, print_team_blue, "%s Player ^3%n^1 changed ^3airaccelerate^1 to^3 %d^1.", g_szPrefix, id, value);
}