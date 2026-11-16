-- Blackbook: German strings (section 10). Any key missing here falls back to
-- the English table through the metatable.
local _, ns = ...

ns.L_DE = setmetatable({
  -- Load and data state.
  MSG_LOADED = "Blackbook geladen. Tippe /bb help für die Befehle.",
  MSG_DB_NEWER = "Deine gespeicherten Daten stammen aus einer neueren Version von Blackbook. Sie bleiben unverändert.",

  -- Slash commands.
  CMD_SETUP = "setup",
  CMD_MINIMAP = "minimap",
  MSG_NOT_AVAILABLE = "%s ist in diesem Build noch nicht verfügbar.",
  MSG_UNKNOWN_COMMAND = "Unbekannter Befehl: %s. Tippe /bb help.",
  MSG_NEED_NAME = "Bitte gib einen Spielernamen an, zum Beispiel /bb %s First Last.",
  MSG_NO_MANAGER = "Das Listenfenster ist in diesem Build noch nicht verfügbar.",
  MSG_NO_UI = "Eine benötigte Vorlage der Oberfläche fehlt, deshalb ist der Editor abgeschaltet.",

  HELP_HEADER = "Blackbook-Befehle:",
  HELP_TOGGLE = "/bb - Listenfenster öffnen oder schließen",
  HELP_LIST = "/bb list - deine Liste anzeigen",
  HELP_IGNORE = "/bb ignore <Name> - einen Spieler ignorieren",
  HELP_WARN = "/bb warn <Name> - vor einem Spieler warnen",
  HELP_REMOVE = "/bb remove <Name> - einen Eintrag löschen",
  HELP_SETUP = "/bb setup - den Einrichtungsassistenten erneut anzeigen",
  HELP_MINIMAP = "/bb minimap - die Minimap-Schaltfläche ein- oder ausblenden",
  HELP_LANG = "/bb lang de|en|auto - die Sprache setzen, danach /reload",
  HELP_VERSION = "/bb version - die installierte Version anzeigen",
  HELP_HELP = "/bb help - diesen Text anzeigen",
  MSG_VERSION = "Version %s.",

  -- Results.
  MSG_LIST_HEADER = "Deine Liste (%d):",
  MSG_LIST_EMPTY = "Deine Liste ist leer.",
  MSG_RECORD_SAVED = "Gespeichert: %s (%s).",
  MSG_RECORD_REMOVED = "Entfernt: %s.",
  MSG_RECORD_NOT_FOUND = "Kein Eintrag für %s.",
  MSG_SELF = "Du kannst deinen eigenen Charakter nicht eintragen.",
  MSG_LANG_SET = "Sprache auf %s gesetzt. Tippe /reload, um sie anzuwenden.",
  MSG_LANG_INVALID = "Nutze /bb lang de, /bb lang en oder /bb lang auto.",

  -- Enforcement (section 6.4).
  MSG_WHISPER_HIDDEN = "Eine Flüsternachricht von %s wurde ausgeblendet.",
  MSG_DECLINED = "%s von %s abgelehnt.",
  MSG_NO_CHAT_FILTER = "Der Chatfilter ist in diesem Client nicht verfügbar, deshalb wird der Chat nicht ausgeblendet.",
  REQ_PARTY = "Eine Gruppeneinladung",
  REQ_GUILD = "Eine Gildeneinladung",
  REQ_DUEL = "Ein Duell",
  REQ_TRADE = "Ein Handel",

  -- Verdicts.
  VERDICT_IGNORE = "Ignorieren",
  VERDICT_WARN = "Warnen",
  VERDICT_NOTICE = "Hinweis",

  -- Editor and context menu (section 9).
  EDITOR_TITLE_NEW = "Zu Blackbook hinzufügen",
  EDITOR_TITLE_EDIT = "Eintrag bearbeiten",
  EDITOR_LABELS_NONE = "Nichts ausgewählt",
  EDITOR_LABELS_COUNT = "%d ausgewählt",
  MSG_NAME_TAKEN = "Für %s gibt es schon einen Eintrag. Bearbeite stattdessen diesen.",
  MSG_NO_MENU = "Die Einbindung ins Rechtsklickmenü ist in diesem Client nicht verfügbar, deshalb fehlen die Menüeinträge.",
  CTX_TITLE = "Blackbook",
  CTX_IGNORE = "Ignorieren...",
  CTX_WARN = "Warnen...",
  CTX_EDIT = "Bearbeiten...",
  CTX_REMOVE = "Entfernen",
  CTX_ADOPT = "Übernehmen...",
  EDITOR_NAME = "Spielername",
  EDITOR_VERDICT = "Urteil",
  EDITOR_LABELS = "Gründe",
  EDITOR_COMMENT = "Kommentar (erforderlich)",
  EDITOR_SAVE = "Speichern",
  EDITOR_CANCEL = "Abbrechen",

  -- Validation.
  ERR_DB = "Die gespeicherten Daten sind noch nicht geladen.",
  ERR_NAME = "Das ist kein gültiger Spielername.",
  ERR_VERDICT = "Wähle Ignorieren oder Warnen.",
  ERR_LABELS = "Wähle mindestens einen Grund.",
  ERR_COMMENT = "Schreibe einen kurzen Kommentar.",
  ERR_COMMENT_LENGTH = "Der Kommentar ist zu lang (höchstens 255 Zeichen).",

  -- Labels (section 5.1).
  LABEL_HARASSMENT = "Beleidigung oder Belästigung",
  LABEL_HATE = "Hassrede",
  LABEL_TOXICITY = "Toxisches Verhalten",
  LABEL_GRIEFING = "Griefing oder Sabotage",
  LABEL_NINJA_LOOT = "Lootdiebstahl",
  LABEL_SCAM = "Betrug",
  LABEL_SPAM = "Spam oder Werbung",
  LABEL_PRIVATE_DISPUTE = "Persönlicher Streit",
  LABEL_OTHER = "Sonstiges",
}, { __index = ns.L })
