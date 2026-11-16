#if defined _hns_match_custom_knifes_included
	#endinput
#endif
#define _hns_match_custom_knifes_included

enum KNIFE_TYPE {
	KNIFE_CLASSIC,
	KNIFE_BATS,
	KNIFE_THROW,
	KNIFE_KATANA,
	KNIFE_NONE
};

/**
* Returns the knife type selected for the current knife round.
*
* @return        Current KNIFE_TYPE value, or KNIFE_NONE outside knife mode
*/
native KNIFE_TYPE:hns_custom_knifes_get_type();
