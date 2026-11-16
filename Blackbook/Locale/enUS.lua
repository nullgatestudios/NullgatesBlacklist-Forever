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

-- Enforcement (section 6.4).
L.MSG_WHISPER_HIDDEN = "Hid a whisper from %s."
L.MSG_DECLINED = "Declined %s from %s."
L.MSG_NO_CHAT_FILTER = "The chat filter is not available in this client, so chat is not hidden."
L.REQ_PARTY = "a party invite"
L.REQ_GUILD = "a guild invite"
L.REQ_DUEL = "a duel"
L.REQ_TRADE = "a trade"

-- Verdicts.
L.VERDICT_IGNORE = "Ignore"
L.VERDICT_WARN = "Warn"
L.VERDICT_NOTICE = "Notice"

-- Editor and context menu (section 9).
L.EDITOR_TITLE_NEW = "Add to Blackbook"
L.EDITOR_TITLE_EDIT = "Edit record"
L.EDITOR_LABELS_NONE = "None selected"
L.EDITOR_LABELS_COUNT = "%d selected"
L.MSG_NAME_TAKEN = "%s already has a record. Edit that one instead."
L.MSG_NO_MENU = "The right-click menu hook is not available in this client, so the menu entries are off."
L.CTX_TITLE = "Blackbook"
L.CTX_IGNORE = "Ignore..."
L.CTX_WARN = "Warn..."
L.CTX_EDIT = "Edit..."
L.CTX_REMOVE = "Remove"
L.CTX_ADOPT = "Adopt..."
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

-- Tooltip (section 6.6).
L.TT_SOURCE = "Imported list: %s by %s"
L.MSG_NO_TOOLTIP = "The tooltip hook is not available in this client, so tooltips are not extended."

-- List window (section 9).
L.TAB_LIST = "My list"
L.TAB_SETTINGS = "Settings"
L.TAB_UNAVAILABLE = "This tab needs interface parts that this client does not have."
L.LIST_SEARCH = "Search"
L.FILTER_ALL = "All"
L.FILTER_ALL_LABELS = "All labels"
L.FILTER_LABELS_COUNT = "%d labels"
L.COL_NAME = "Name"
L.COL_VERDICT = "Verdict"
L.COL_LABELS = "Labels"
L.COL_COMMENT = "Comment"
L.COL_DATE = "Date"
L.LIST_ADD_NAME = "Add player"
L.LIST_ADD = "Add..."
L.LIST_COUNT = "%d of %d records"
L.LIST_HINT = "Click: edit    Shift-click: delete"

-- Settings tab and minimap button.
L.OPT_LANGUAGE = "Language"
L.LANG_AUTO = "Automatic"
L.LANG_EN = "English"
L.LANG_DE = "Deutsch"
L.OPT_ENFORCEMENT = "Enforcement"
L.OPT_HIDE_CHAT = "Hide chat from ignored players"
L.OPT_AUTO_DECLINE = "Decline invites, duels and trades from ignored players"
L.OPT_SHOW_NOTICES = "Show a notice when something is blocked"
L.OPT_SHOW_MINIMAP = "Show the minimap button"
L.MINIMAP_TOOLTIP_COUNT = "%d records"
L.MINIMAP_TOOLTIP_HINT = "Left-click: open the list. Drag: move the button."
L.MSG_MINIMAP_SHOWN = "Minimap button shown."
L.MSG_MINIMAP_HIDDEN = "Minimap button hidden."
