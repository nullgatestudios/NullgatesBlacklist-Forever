-- Blackbook: English strings (section 10). Keys are stable; German lives in
-- deDE.lua and falls back to this table.
local _, ns = ...

local L = {}
ns.L = L

-- Load and data state.
L.MSG_LOADED = "Blackbook loaded. Type /bb help for the commands."
L.MSG_DB_NEWER = "Your saved data comes from a newer version of Blackbook. It is left unchanged."

-- Slash commands.
L.CMD_SETUP = "setup"
L.CMD_MINIMAP = "minimap"
L.MSG_NOT_AVAILABLE = "%s is not available in this build yet."
L.MSG_UNKNOWN_COMMAND = "Unknown command: %s. Type /bb help."
L.MSG_NEED_NAME = "Please give a player name, for example /bb %s First Last."
L.MSG_NO_MANAGER = "The list window is not available in this build yet."
L.MSG_NO_UI = "A required interface template is missing, so the editor is turned off."

L.HELP_HEADER = "Blackbook commands:"
L.HELP_TOGGLE = "/bb - open or close the list window"
L.HELP_LIST = "/bb list - show your list"
L.HELP_IGNORE = "/bb ignore <name> - ignore a player"
L.HELP_WARN = "/bb warn <name> - warn about a player"
L.HELP_REMOVE = "/bb remove <name> - delete a record"
L.HELP_SETUP = "/bb setup - show the setup wizard again"
L.HELP_MINIMAP = "/bb minimap - show or hide the minimap button"
L.HELP_LANG = "/bb lang de|en|auto - set the language, then /reload"
L.HELP_VERSION = "/bb version - show the installed version"
L.HELP_HELP = "/bb help - show this text"
L.MSG_VERSION = "Version %s."

-- Results.
L.MSG_LIST_HEADER = "Your list (%d):"
L.MSG_LIST_EMPTY = "Your list is empty."
L.MSG_RECORD_SAVED = "Saved: %s (%s)."
L.MSG_RECORD_REMOVED = "Removed: %s."
L.MSG_RECORD_NOT_FOUND = "No record for %s."
L.MSG_SELF = "You cannot add your own character."
L.MSG_LANG_SET = "Language set to %s. Type /reload to apply it."
L.MSG_LANG_INVALID = "Use /bb lang de, /bb lang en or /bb lang auto."

-- Verdicts.
L.VERDICT_IGNORE = "Ignore"
L.VERDICT_WARN = "Warn"
L.VERDICT_NOTICE = "Notice"

-- Temporary editor (replaced by UI/Editor.lua in M3).
L.EDITOR_TITLE = "Blackbook record"
L.EDITOR_NAME = "Player name"
L.EDITOR_VERDICT = "Verdict"
L.EDITOR_LABELS = "Labels"
L.EDITOR_COMMENT = "Comment (required)"
L.EDITOR_SAVE = "Save"
L.EDITOR_CANCEL = "Cancel"

-- Validation.
L.ERR_DB = "The saved data is not loaded yet."
L.ERR_NAME = "That is not a valid player name."
L.ERR_VERDICT = "Choose ignore or warn."
L.ERR_LABELS = "Choose at least one label."
L.ERR_COMMENT = "Write a short comment."
L.ERR_COMMENT_LENGTH = "The comment is too long (maximum 255 characters)."

-- Labels (section 5.1).
L.LABEL_HARASSMENT = "Insults or harassment"
L.LABEL_HATE = "Hate speech"
L.LABEL_TOXICITY = "Toxic behavior"
L.LABEL_GRIEFING = "Griefing or sabotage"
L.LABEL_NINJA_LOOT = "Loot stealing"
L.LABEL_SCAM = "Scam"
L.LABEL_SPAM = "Spam or advertising"
L.LABEL_PRIVATE_DISPUTE = "Private dispute"
L.LABEL_OTHER = "Other"
