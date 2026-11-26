extends Node

signal language_changed(lang: String)

var current_lang: String = "en"

const STRINGS: Dictionary = {
	"GAME_TITLE": {
		"ru": "МЁРТВЫЙ ДЕЦИБЕЛ",
		"en": "DEAD DECIBEL"
	},
	"GAME_SUBTITLE": {
		"ru": "Кооперативный акустический хоррор  ·  Без таймеров, храни тишину",
		"en": "Co-op acoustic survival horror  ·  No timers, every sound counts"
	},
	"MENU_PLAY_SOLO": {
		"ru": "Одиночная вылазка",
		"en": "Solo infiltration"
	},
	"MENU_PLAY_COOP": {
		"ru": "Кооператив (1–4 игрока)",
		"en": "Co-op squad (1–4)"
	},
	"MENU_SETTINGS": {
		"ru": "Настройки",
		"en": "Settings"
	},
	"MENU_HOW_TO_PLAY": {
		"ru": "Полевой справочник",
		"en": "Field manual"
	},
	"MENU_QUIT": {
		"ru": "Выход",
		"en": "Quit"
	},
	"MENU_BACK": {
		"ru": "Назад",
		"en": "Back"
	},
	"DIFF_TITLE": {
		"ru": "Режим допуска",
		"en": "Clearance mode"
	},
	"DIFF_PRACTICE": {
		"ru": "Разведка — без Слухача-07, спокойное изучение всех 14 отсеков",
		"en": "Recon — no Listener-07, explore all 14 sectors freely"
	},
	"DIFF_NORMAL": {
		"ru": "Стандарт — без лимита времени, шанс выбраться из изолятора",
		"en": "Standard — no time limit, escape from holding cage if caught"
	},
	"DIFF_NIGHTMARE": {
		"ru": "Кошмар — острый слух, выбивание дверей, тяжёлое ранение со старта",
		"en": "Nightmare — acute sonar, door-smashing frenzy, critical start"
	},
	"START_GAME_BTN": {
		"ru": "Начать спуск",
		"en": "Begin descent"
	},
	"COOP_TITLE": {
		"ru": "Связь группы (до 4 выживших)",
		"en": "Squad uplink (up to 4 survivors)"
	},
	"COOP_NAME_LABEL": {
		"ru": "Позывной:",
		"en": "Callsign:"
	},
	"COOP_SERVER_LABEL": {
		"ru": "Адрес ретранслятора (WebSocket):",
		"en": "Relay address (WebSocket):"
	},
	"COOP_CREATE_BTN": {
		"ru": "Создать канал",
		"en": "Create room"
	},
	"COOP_JOIN_BTN": {
		"ru": "Войти по коду",
		"en": "Join by code"
	},
	"COOP_COPY_CODE": {
		"ru": "Скопировать код",
		"en": "Copy code"
	},
	"COOP_REFRESH_PUBLIC": {
		"ru": "Открытые группы",
		"en": "Open rooms"
	},
	"COOP_ROOM_STATUS_NONE": {
		"ru": "Канал не выбран. Создайте комнату или введите 4-буквенный код напарника.",
		"en": "No active channel. Create a room or enter your teammate's 4-letter code."
	},
	"COOP_ROOM_STATUS_ACTIVE": {
		"ru": "Канал %s  ·  Группа %d/4  ·  %s",
		"en": "Channel %s  ·  Squad %d/4  ·  %s"
	},
	"ROLE_HOST": {
		"ru": "Ведущий",
		"en": "Host"
	},
	"ROLE_CLIENT": {
		"ru": "Боец",
		"en": "Operative"
	},
	"COOP_START_MATCH": {
		"ru": "Начать вылазку для группы",
		"en": "Deploy squad"
	},
	"COOP_WAITING_HOST": {
		"ru": "Ожидание команды ведущего...",
		"en": "Waiting for host deployment..."
	},
	"SETTINGS_TITLE": {
		"ru": "Параметры",
		"en": "Settings"
	},
	"SET_SENS": {
		"ru": "Чувствительность обзора",
		"en": "Look sensitivity"
	},
	"SET_VOL": {
		"ru": "Общая громкость",
		"en": "Master volume"
	},
	"SET_MIC": {
		"ru": "Рация и микрофон",
		"en": "Voice & microphone"
	},
	"MIC_AUTO": {
		"ru": "Авто (голос слышен монстру)",
		"en": "Auto (voice attracts monster)"
	},
	"MIC_PTT": {
		"ru": "По клавише [V]",
		"en": "Push-to-talk [V]"
	},
	"MIC_OFF": {
		"ru": "Отключён",
		"en": "Muted"
	},
	"SET_LANG": {
		"ru": "Язык: Русский",
		"en": "Language: English"
	},
	"SET_GYRO": {
		"ru": "Гироскоп (мобильный)",
		"en": "Gyroscope (mobile)"
	},
	"SET_HAPTICS": {
		"ru": "Виброотклик",
		"en": "Haptics & vibration"
	},
	"SET_REDUCE_MOTION": {
		"ru": "Уменьшить тряску и пульсацию",
		"en": "Reduce motion & shake"
	},
	"ON": {
		"ru": "Вкл",
		"en": "On"
	},
	"OFF": {
		"ru": "Выкл",
		"en": "Off"
	},
	"HOW_TITLE": {
		"ru": "Протокол выживания на объекте",
		"en": "Facility survival protocol"
	},
	"HOW_BODY": {
		"ru": "1. Бронешлюз эвакуации (Северный сектор):\n   Снимите 4 блокировки без каких-либо ограничений по времени:\n   · Сорвите доски монтировкой, перекусите силовой кабель болторезом.\n   · Установите предохранитель в энергоблоке и подайте ток.\n   · Найдите папку с кодом, откройте сейф охраны и заберите мастер-ключ.\n\n2. Повадки Слухача-07:\n   · Он слеп, но использует эхолокацию у дверных проёмов и проверяет подозрительные шкафы.\n   · Удерживайте [ПРОБЕЛ] (кнопку лёгких или [LT] на геймпаде), чтобы задержать дыхание, когда он пускает сонар или прислушивается к укрытию.\n   · Смотрите под ноги: битое стекло и ржавые коляски выдают вас грохотом.\n\n3. Управление, приманки и спасение группы:\n   · [WASD] шаг · [Shift] бег · [C / Ctrl] присед · [F] фонарь · [R] быстрая замена батареи из любого слота.\n   · [E / ЛКМ] действие · [ПКМ] применить расходник или бросить бутылку/фальшфейер напрямую · [G / Q] бросить или выложить предмет · [Tab / J] досье · [1–5 / Колесо] слоты · [V] рация.\n   · Геймпад (DualSense / Xbox): левый стик — шаг, правый — обзор, A/X — действие, B — присед, Y — фонарь, LB/RB — слоты, крестовина вниз — бросок, LT — дыхание, L3 — бег, View — досье.\n   · Откручивайте решётки вентиляции отвёрткой для тихого обхода; включайте громкоговорители и спасайте напарников из клетки в Хирургии.",
		"en": "1. Evacuation blast gate (North sector):\n   Clear all 4 physical locks with zero time limit:\n   · Pry planks with the crowbar and cut the power cable with bolt cutters.\n   · Install the high-voltage fuse in the substation generator.\n   · Find the code dossier, unlock Security's wall safe, and take the master key.\n\n2. Listener-07 hunting behavior:\n   · Blind, but uses doorway echolocation clicks and sniffs suspicious lockers.\n   · Hold [SPACE] (or Lungs button / Gamepad [LT]) to hold your breath when he inspects your locker or emits sonar.\n   · Watch your step: broken glass shards and rusted wheelchairs make loud noise.\n\n3. Controls, lures & squad rescue:\n   · [WASD] move · [Shift] sprint · [C / Ctrl] crouch · [F] flashlight · [R] quick-reload battery from any inventory slot.\n   · [E / LMB] interact · [RMB] quick-use held consumable or throw bottle/flare directly · [G / Q] drop/throw · [Tab / J] dossier · [1–5 / Wheel] slots · [V] PTT radio.\n   · Gamepad (DualSense / Xbox): Left Stick move, Right Stick look, A/X interact, B crouch, Y flashlight, LB/RB cycle slots, D-Pad Down drop/throw, LT hold breath, L3 sprint toggle, Back/View dossier.\n   · Unscrew vent grates with a screwdriver for silent wing shortcuts; trigger PA sirens and rescue teammates from the Surgery cage."
	},
	# --- HUD, DOSSIER & INSTRUMENT READOUTS ---
	"OBJ_HEADER": {
		"ru": "Блокировки шлюза · %d из 4",
		"en": "Airlock seals · %d of 4"
	},
	"OBJ_PLANKS": {
		"ru": "Доски на створе (монтировка)",
		"en": "Barricade planks (crowbar)"
	},
	"OBJ_CABLE": {
		"ru": "Силовой кабель (кусачки)",
		"en": "Security cable (cutters)"
	},
	"OBJ_POWER": {
		"ru": "Питание энергоблока (предохранитель)",
		"en": "Substation power (fuse)"
	},
	"OBJ_PADLOCK": {
		"ru": "Навесной замок (мастер-ключ из сейфа)",
		"en": "Heavy padlock (safe master key)"
	},
	"OBJ_OPEN_EXIT": {
		"ru": "Все блокировки сняты — откройте северный шлюз",
		"en": "All seals cleared — open north evacuation gate"
	},
	"DOSSIER_BTN": {
		"ru": "Досье [%d/4]",
		"en": "Dossier [%d/4]"
	},
	"DOSSIER_HINT_KEY": {
		"ru": "[TAB] Скрыть сводку",
		"en": "[TAB] Hide dossier"
	},
	"RADAR_RECON": {
		"ru": "РАЗВЕДКА",
		"en": "RECON"
	},
	"RADAR_COOP": {
		"ru": "КАНАЛ %s",
		"en": "CH %s"
	},
	"VITALS_HEALTHY": {
		"ru": "Пульс ровный",
		"en": "Stable"
	},
	"VITALS_WOUNDED": {
		"ru": "Тяжёлое ранение (нужна аптечка)",
		"en": "Wounded (find medkit)"
	},
	"VITALS_CAGED": {
		"ru": "В изоляторе",
		"en": "Caged"
	},
	"BREATH_HOLDING": {
		"ru": "Дыхание задержано",
		"en": "Holding breath"
	},
	"POSTURE_STAND": {
		"ru": "В полный рост",
		"en": "Standing"
	},
	"POSTURE_CROUCH": {
		"ru": "Присев (тихо)",
		"en": "Crouching"
	},
	"POSTURE_HIDDEN": {
		"ru": "В укрытии",
		"en": "Hidden"
	},
	"POSTURE_SPRINT": {
		"ru": "Бег",
		"en": "Sprinting"
	},
	"POSTURE_DOWNED": {
		"ru": "Ранен",
		"en": "Downed"
	},
	"CONTROL_HINT_BAR": {
		"ru": "[E] Действие · [ПКМ] Применить/Бросок · [R] Батарея · [F] Фонарь · [C] Присед · [ПРОБЕЛ] Дыхание",
		"en": "[E] Interact · [RMB] Use/Throw · [R] Battery · [F] Light · [C] Crouch · [SPACE] Breath"
	},
	"STATUS_ECHOLOCATE": {
		"ru": "Слухач-07 пускает эхолокацию — замрите или задержите дыхание",
		"en": "Listener-07 echolocating — freeze or hold breath"
	},
	"STATUS_SNIFFING": {
		"ru": "Он прислушивается к укрытию — задержите дыхание [ПРОБЕЛ]",
		"en": "He is listening at your hiding spot — hold breath [SPACE]"
	},
	"STATUS_STUNNED": {
		"ru": "Слухач-07 оглушён вспышкой",
		"en": "Listener-07 stunned by flare"
	},
	"STATUS_ALERT": {
		"ru": "Слухач-07 идёт на звук",
		"en": "Listener-07 tracking sound"
	},
	"STATUS_CHASE": {
		"ru": "Погоня — разорвите линию обзора",
		"en": "Pursuit — break line of sight"
	},
	"STATUS_HIDING": {
		"ru": "В шкафу · [E] выйти · [ПРОБЕЛ] задержать дыхание",
		"en": "In locker · [E] exit · [SPACE] hold breath"
	},
	"STATUS_DOWNED": {
		"ru": "Ранение — ползите к укрытию или ждите напарника (%d с)",
		"en": "Downed — crawl to cover or await teammate (%ds)"
	},
	"STATUS_ALLY_DOWN": {
		"ru": "Напарник %s ранен — отмечен на радаре",
		"en": "Teammate %s downed — marked on radar"
	},
	# --- ITEMS ---
	"ITEM_crowbar": {
		"ru": "Монтировка",
		"en": "Crowbar"
	},
	"ITEM_cutters": {
		"ru": "Болторез",
		"en": "Bolt cutters"
	},
	"ITEM_fuse": {
		"ru": "Высоковольтный предохранитель",
		"en": "High-voltage fuse"
	},
	"ITEM_key": {
		"ru": "Мастер-ключ",
		"en": "Master key"
	},
	"ITEM_code_note": {
		"ru": "Код сейфа: %s",
		"en": "Safe code: %s"
	},
	"ITEM_bottle": {
		"ru": "Стеклянная бутылка (приманка)",
		"en": "Glass bottle (decoy)"
	},
	"ITEM_syringe": {
		"ru": "Инъектор адреналина",
		"en": "Adrenaline injector"
	},
	"ITEM_battery": {
		"ru": "Аккумулятор фонаря",
		"en": "Flashlight cell"
	},
	"ITEM_flare": {
		"ru": "Шумовой фальшфейер (оглушает)",
		"en": "Sonic flare (stuns stalker)"
	},
	"ITEM_medkit": {
		"ru": "Полевая аптечка (лечит раны)",
		"en": "Field medkit (heals wounds)"
	},
	"ITEM_screwdriver": {
		"ru": "Отвёртка (тихий доступ к вентиляции)",
		"en": "Screwdriver (silent vent access)"
	},
	# --- INTERACTION PROMPTS ---
	"PROMPT_TAKE": {
		"ru": "Взять · %s",
		"en": "Take · %s"
	},
	"PROMPT_INV_FULL": {
		"ru": "Свободных слотов нет — освободите руку [G]",
		"en": "Inventory full — drop equipped item [G]"
	},
	"PROMPT_DOOR_OPEN": {
		"ru": "Открыть дверь",
		"en": "Open door"
	},
	"PROMPT_DOOR_CLOSE": {
		"ru": "Прикрыть дверь",
		"en": "Close door"
	},
	"PROMPT_HIDE_LOCKER": {
		"ru": "Укрыться в шкафу",
		"en": "Hide inside locker"
	},
	"PROMPT_EXIT_LOCKER": {
		"ru": "Выйти из шкафа",
		"en": "Step out of locker"
	},
	"PROMPT_SEARCH_DRAWER": {
		"ru": "Осмотреть ящик",
		"en": "Search drawer"
	},
	"PROMPT_VENT_UNSCREW": {
		"ru": "Тихо открутить решётку (отвёртка)",
		"en": "Silently unscrew vent grate (screwdriver)"
	},
	"PROMPT_VENT_FORCE": {
		"ru": "Выбить решётку вентиляции (шумно)",
		"en": "Wrench vent grate open (loud)"
	},
	"PROMPT_PA_LURE": {
		"ru": "Включить сирену в дальнем крыле (отвлечь монстра)",
		"en": "Broadcast siren in distant wing (lure monster)"
	},
	"PROMPT_PA_COOLDOWN": {
		"ru": "Интерком перезаряжается (%d с)",
		"en": "Intercom recharging (%ds)"
	},
	"PROMPT_CAGE_UNLOCK": {
		"ru": "Отодвинуть засов клетки изолятора",
		"en": "Slide holding cage latch open"
	},
	"PROMPT_SELF_REVIVE": {
		"ru": "Вколоть адреналин и встать на ноги",
		"en": "Inject adrenaline to self-revive"
	},
	"PROMPT_SAFE_ENTER": {
		"ru": "Ввести 4-значный код сейфа",
		"en": "Enter 4-digit safe code"
	},
	"PROMPT_SAFE_OPENED": {
		"ru": "Сейф разблокирован",
		"en": "Safe unlocked"
	},
	"PROMPT_GEN_NEED_FUSE": {
		"ru": "Энергоблок обесточен — нужен предохранитель",
		"en": "Substation offline — requires high-voltage fuse"
	},
	"PROMPT_GEN_INSERT": {
		"ru": "Установить предохранитель и подать питание",
		"en": "Install fuse & restore facility power"
	},
	"PROMPT_GEN_ONLINE": {
		"ru": "Питание подано на северный бронешлюз",
		"en": "Power routed to north evacuation airlock"
	},
	"PROMPT_EXIT_PRY": {
		"ru": "Сорвать доски монтировкой",
		"en": "Pry planks with crowbar"
	},
	"PROMPT_EXIT_CUT": {
		"ru": "Перекусить силовой кабель",
		"en": "Sever security cable"
	},
	"PROMPT_EXIT_UNLOCK": {
		"ru": "Открыть замок мастер-ключом",
		"en": "Unlock padlock with master key"
	},
	"PROMPT_EXIT_ESCAPE": {
		"ru": "Разблокировать бронешлюз и покинуть этаж",
		"en": "Open blast gate & evacuate"
	},
	"PROMPT_EXIT_LOCKED": {
		"ru": "Шлюз заперт · осталось защит: %d",
		"en": "Airlock sealed · %d locks remaining"
	},
	"PROMPT_REVIVE_ALLY": {
		"ru": "Поднять напарника · %s",
		"en": "Revive teammate · %s"
	},
	# --- MODALS & ENDINGS ---
	"SAFE_MODAL_TITLE": {
		"ru": "Терминал сейфа охраны",
		"en": "Security safe keypad"
	},
	"SAFE_KNOWN_CODE": {
		"ru": "Записанный код в досье: %s",
		"en": "Recorded dossier code: %s"
	},
	"SAFE_NO_NOTE": {
		"ru": "Код неизвестен — осмотрите столы и картотеки комплекса",
		"en": "Code unknown — search laboratory desks and archive cabinets"
	},
	"PAUSE_TITLE": {
		"ru": "Пауза",
		"en": "Paused"
	},
	"PAUSE_RESUME": {
		"ru": "Продолжить",
		"en": "Resume"
	},
	"PAUSE_RESTART": {
		"ru": "Новая вылазка",
		"en": "New descent"
	},
	"PAUSE_MAIN_MENU": {
		"ru": "Главное меню",
		"en": "Main menu"
	},
	"CAGE_TRANSITION_TITLE": {
		"ru": "Хирургический изолятор",
		"en": "Surgical holding cage"
	},
	"CAGE_TRANSITION_SUB": {
		"ru": "Слухач-07 запер вас в клетке западного блока. Снаряжение при вас — отоприте засов, когда шаги стихнут, и найдите аптечку.",
		"en": "Listener-07 locked you in the West Surgery cage. Gear intact — unlatch the bars once footsteps fade and find a medkit."
	},
	"VICTORY_TITLE": {
		"ru": "Эвакуация завершена",
		"en": "Evacuation complete"
	},
	"VICTORY_STATS": {
		"ru": "Северный бронешлюз пройден  ·  Время на объекте: %s",
		"en": "North blast gate cleared  ·  Time in facility: %s"
	},
	"GAMEOVER_TITLE": {
		"ru": "Связь с группой потеряна",
		"en": "Signal lost"
	},
	"GAMEOVER_SUB": {
		"ru": "Критические ранения не оставили шансов выбраться из комплекса НИИ-07.",
		"en": "Critical trauma ended the escape attempt inside NII-07."
	},
	"TOAST_SYRINGE_USED": {
		"ru": "Адреналин введён — бесшумный рывок на 10 секунд",
		"en": "Adrenaline active — silent sprint for 10 seconds"
	},
	"TOAST_MEDKIT_USED": {
		"ru": "Раны перевязаны — здоровье полностью восстановлено",
		"en": "Wounds treated — full resilience restored"
	},
	"TOAST_FLARE_USED": {
		"ru": "Фальшфейер брошен — вспышка оглушит Слухача-07",
		"en": "Sonic flare deployed — strobe shriek stuns Listener-07"
	},
	"TOAST_BATTERY_USED": {
		"ru": "Аккумулятор заменён — заряд фонаря 100%",
		"en": "Battery cell replaced — flashlight at 100%"
	},
	"TOAST_CODE_FOUND": {
		"ru": "В досье записан код сейфа: %s",
		"en": "Safe code logged to dossier: %s"
	},
	"TOAST_PA_TRIGGERED": {
		"ru": "Сирена включена в секторе «%s» — Слухач-07 уходит на звук",
		"en": "Siren triggered in %s — Listener-07 lured away"
	},
	"TOAST_GASP": {
		"ru": "Воздух закончился — громкий вдох выдал позицию",
		"en": "Out of breath — loud gasp echoed nearby"
	},
	"TOAST_MP_SYNC": {
		"ru": "Вы подключились к вылазке ведущего — мир синхронизирован",
		"en": "Joined the host's descent — world synchronized"
	},
	"COOP_RELAY_HINT": {
		"ru": "Через интернет: wss://-адрес туннеля ведущего. В одной Wi-Fi сети: ws://IP-адрес ведущего:8787",
		"en": "Over internet: host's wss:// tunnel address. Same Wi-Fi: ws://HOST-IP:8787"
	},
	# --- FIELD ORIENTATION TUTORIAL ---
	"TUT_HEADER": {
		"ru": "Полевой инструктаж",
		"en": "Field orientation"
	},
	"TUT_SKIP": {
		"ru": "Пропустить [K]",
		"en": "Skip [K]"
	},
	"TUT_NEXT": {
		"ru": "Далее",
		"en": "Next"
	},
	"TUT_DONE": {
		"ru": "Готово",
		"en": "Done"
	},
	"TUT_STEP_1": {
		"ru": "Двигайтесь [WASD] и нажмите [C], чтобы присесть — бег разносится эхом по всему НИИ-07.",
		"en": "Move with [WASD] and press [C] to crouch silently — running echoes across NII-07."
	},
	"TUT_STEP_2": {
		"ru": "Переключите фонарь [F] и подберите стартовый инструмент [E] прямо впереди в палате Б-04.",
		"en": "Toggle flashlight [F] and pick up the starter tool [E] right ahead in Ward B-04."
	},
	"TUT_STEP_3": {
		"ru": "Удерживайте [ПРОБЕЛ], чтобы задержать дыхание, когда Слухач-07 пускает сонар или проверяет шкаф.",
		"en": "Hold [SPACE] to silence your breath when Listener-07 echolocates or sniffs your locker."
	},
	"TUT_STEP_4": {
		"ru": "Нажмите [TAB], чтобы открыть Досье. Снимите 4 блокировки Северного шлюза — без лимита времени.",
		"en": "Press [TAB] to check your Dossier. Clear all 4 locks on the North Airlock to escape — zero time limit."
	},
	"TUT_STEP_1_TOUCH": {
		"ru": "Двигайтесь левым стиком и нажмите кнопку приседа — бег разносится эхом по всему НИИ-07.",
		"en": "Move with the left thumbstick and tap Crouch to move silently — running echoes across NII-07."
	},
	"TUT_STEP_2_TOUCH": {
		"ru": "Нажмите кнопку фонаря и подберите стартовый инструмент кнопкой действия в палате Б-04.",
		"en": "Tap Flashlight and pick up the starter tool with the Interact button ahead in Ward B-04."
	},
	"TUT_STEP_3_TOUCH": {
		"ru": "Удерживайте кнопку лёгких, чтобы задержать дыхание при сонаре или проверке шкафа.",
		"en": "Hold the Lungs button to silence your breath when Listener-07 echolocates or sniffs your locker."
	},
	"TUT_STEP_4_TOUCH": {
		"ru": "Нажмите кнопку Досье вверху слева. Снимите 4 блокировки Северного шлюза — без лимита времени.",
		"en": "Tap Dossier at top-left. Clear all 4 locks on the North Airlock to escape — zero time limit."
	},
	"SET_REPLAY_TUTORIAL": {
		"ru": "Повторить обучение",
		"en": "Replay tutorial"
	}
}


func _ready() -> void:
	current_lang = "en"


func set_language(lang: String) -> void:
	if lang in ["ru", "en"]:
		current_lang = lang
		language_changed.emit(current_lang)


func toggle_language() -> void:
	set_language("en" if current_lang == "ru" else "ru")


func t(key: String) -> String:
	if STRINGS.has(key):
		var entry: Dictionary = STRINGS[key]
		if entry.has(current_lang):
			return entry[current_lang]
		return entry.get("en", key)
	return key
