class_name TutorialSteps
extends RefCounted

## Static step data for the first-launch tutorial. Each step names a target
## the caller (home_panel.gd / main.gd) resolves into a screen-space Rect2 —
## this class only owns the text/ordering, not node lookups.

## "gated" steps wait for the player's real tap to perform the actual game
## action (the match stays unpaused, no tap-anywhere catcher); the rest are
## purely informational callouts (match paused, tap anywhere to continue).
const STEPS := [
	{"scene": "lobby", "target": "level1", "text": "Tap Level 1 to start your first match!", "tap_to_continue": false, "gated": true},
	{"scene": "main", "target": "buy_slot", "text": "Tap an empty tile to buy a cat!", "tap_to_continue": false, "gated": true},
	{"scene": "main", "target": "merge_hint", "text": "Drag two matching cats together to merge them into a stronger one!", "tap_to_continue": true, "gated": false},
	{"scene": "main", "target": "wall", "text": "Zombies will attack your wall — don't let it break!", "tap_to_continue": true, "gated": false},
	{"scene": "main", "target": "repair_button", "text": "Tap here to repair the wall using coins.", "tap_to_continue": true, "gated": false},
	{"scene": "main", "target": "item_buttons", "text": "Use items like spikes and TNT to turn the tide of battle!", "tap_to_continue": true, "gated": false},
]
