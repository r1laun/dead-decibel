extends Node

signal language_changed(lang: String)

var current_lang: String = "en"

const STRINGS: Dictionary = {
	"GAME_TITLE": {
		"ru": "МЁРТВЫЙ ДЕЦИБЕЛ",
		"en": "DEAD DECIBEL"
	},
	"GAME_SUBTITLE": {
		"ru": "Бункер НИИ-07, карантинный этаж\nБез таймеров",
		"en": "Bunker NII-07, Quarantine Floor\nNo timers"
	},
	"MENU_PLAY_SOLO": {
		"ru": "Одиночная игра",
		"en": "Solo"
	},
	"MENU_PLAY_COOP": {
		"ru": "Кооператив (1–4)",
		"en": "Co-op (1–4)"
	},
	"MENU_SETTINGS": {
		"ru": "Настройки",
		"en": "Settings"
	},
	"MENU_HOW_TO_PLAY": {
		"ru": "Как играть",
		"en": "How to play"
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
		"ru": "Сложность",
		"en": "Difficulty"
	},
	"DIFF_PRACTICE": {
		"ru": "Разведка: Слухача-07 нет, все 14 отсеков открыты",
		"en": "Practice: no Listener-07, walk all 14 rooms safely"
	},
	"DIFF_NORMAL": {
		"ru": "Обычный: без таймера, из изолятора можно выбраться",
		"en": "Normal: no time limit, break out of the cage if caught"
	},
	"DIFF_NIGHTMARE": {
		"ru": "Кошмар: слышит дальше, ломает двери, старт с ранением",
		"en": "Nightmare: sharper hearing, breaks down doors, start wounded"
	},
	"START_GAME_BTN": {
		"ru": "Играть",
		"en": "Play"
	},
	"COOP_TITLE": {
		"ru": "Кооператив (до 4 игроков)",
		"en": "Co-op (up to 4 players)"
	},
	"COOP_NAME_LABEL": {
		"ru": "Позывной:",
		"en": "Callsign:"
	},
	"COOP_SERVER_LABEL": {
		"ru": "Сервер (WebSocket):",
		"en": "Server (WebSocket):"
	},
	"COOP_CREATE_BTN": {
		"ru": "Создать комнату",
		"en": "Create room"
	},
	"COOP_JOIN_BTN": {
		"ru": "Войти по коду",
		"en": "Join by code"
	},
	"COOP_COPY_CODE": {
		"ru": "Копировать код",
		"en": "Copy code"
	},
	"COOP_REFRESH_PUBLIC": {
		"ru": "Открытые комнаты",
		"en": "Open rooms"
	},
	"COOP_ROOM_STATUS_NONE": {
		"ru": "Вы не в комнате. Создайте свою или введите код из 4 букв.",
		"en": "Not in a room. Create one or enter a 4-letter code."
	},
	"COOP_ROOM_STATUS_ACTIVE": {
		"ru": "Комната %s  ·  Игроков: %d/4  ·  %s",
		"en": "Room %s  ·  %d/4 players  ·  %s"
	},
	"ROLE_HOST": {
		"ru": "Хост",
		"en": "Host"
	},
	"ROLE_CLIENT": {
		"ru": "Игрок",
		"en": "Player"
	},
	"COOP_START_MATCH": {
		"ru": "Начать игру",
		"en": "Start game"
	},
	"COOP_WAITING_HOST": {
		"ru": "Ждём запуска от хоста...",
		"en": "Waiting for host to start..."
	},
	"SETTINGS_TITLE": {
		"ru": "Настройки",
		"en": "Settings"
	},
	"SET_SENS": {
		"ru": "Чувствительность",
		"en": "Look sensitivity"
	},
	"SET_VOL": {
		"ru": "Громкость",
		"en": "Volume"
	},
	"SET_MIC": {
		"ru": "Микрофон",
		"en": "Microphone"
	},
	"MIC_AUTO": {
		"ru": "Всегда (монстр слышит)",
		"en": "Always on (monster hears you)"
	},
	"MIC_PTT": {
		"ru": "По кнопке [V]",
		"en": "Push-to-talk [V]"
	},
	"MIC_OFF": {
		"ru": "Выкл",
		"en": "Off"
	},
	"SET_LANG": {
		"ru": "Язык: Русский",
		"en": "Language: English"
	},
	"SET_GYRO": {
		"ru": "Гироскоп (телефон)",
		"en": "Gyroscope (mobile)"
	},
	"SET_HAPTICS": {
		"ru": "Вибрация",
		"en": "Vibration"
	},
	"SET_REDUCE_MOTION": {
		"ru": "Меньше тряски",
		"en": "Reduce motion"
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
		"ru": "Как играть",
		"en": "How to play"
	},
	"HOW_BODY": {
		"ru": "1. Сенсорное управление (телефон / планшет):\n- Левый стик: лёгкий наклон для шага, до внешнего края для бега.\n- Правая часть экрана: ведите пальцем для обзора, двойное касание для действия (двери, предметы, шкаф, сейф, генератор, клетка). Можно нажать и прямо на подсказку по центру.\n- Кнопки справа: фонарь, присед, задержка дыхания (удерживайте) и бросок/сброс (появляется, когда в руках предмет).\n\n2. Клавиатура и геймпад:\n- Клавиатура: WASD идти, Shift бежать, C / Ctrl присесть, E / ЛКМ действие, F фонарь, R сменить батарею, ПКМ / G / Q применить или бросить, Пробел задержать дыхание, Tab / J досье, 1-5 / Колесо слоты, V рация.\n- Геймпад: левый стик идти, правый обзор, A/X действие, B присед, Y фонарь, LB/RB слоты, вниз бросить, вверх батарея, LT дыхание, L3 бег, View досье.\n\n3. Выход через северный шлюз:\n- Таймера нет. Снимите 4 замка со шлюза: доски (монтировка), кабель (болторез), энергоблок (предохранитель), замок (мастер-ключ из сейфа).\n- Слухач-07 слеп, но прощупывает комнаты сонаром у дверей и проверяет шкафы. При звуке сонара или шагах у шкафа задержите дыхание. Битое стекло и коляски обходите в приседе.\n- Решётки вентиляции откручиваются отвёрткой без шума. Сирены на стенах отвлекают монстра, а пойманных напарников можно выпустить из клетки в Хирургии.",
		"en": "1. Touch controls (phone / tablet):\n- Left stick: push lightly to walk, push to the outer ring to sprint.\n- Right side of screen: drag to look around, double-tap to interact with doors, items, lockers, the safe, generator, or cage. You can also tap the center prompt.\n- Right buttons: Flashlight, Crouch, Hold Breath (press and hold), and Drop/Throw (shown when holding an item).\n\n2. PC & Gamepad:\n- Keyboard: WASD move, Shift sprint, C / Ctrl crouch, E / Left Click interact, F flashlight, R swap battery, Right Click / G / Q use or drop, Space hold breath, Tab / J dossier, 1-5 / Wheel slots, V push-to-talk.\n- Gamepad: Left Stick move, Right Stick look, A/X interact, B crouch, Y flashlight, LB/RB slots, D-Pad Down drop, D-Pad Up swap battery, LT hold breath, L3 sprint, View dossier.\n\n3. Escaping NII-07:\n- Clear 4 locks on the North Airlock with no time limit: planks (crowbar), cable (bolt cutters), power unit (fuse), and padlock (master key inside the safe).\n- Listener-07 is blind. It clicks at doorways to scan rooms and checks lockers. Hold your breath when it scans or listens nearby, and crouch past broken glass and wheelchairs.\n- Use a screwdriver to open vents quietly, trigger intercom sirens to draw it away, and free trapped teammates from the Surgery cage."
	},
	# --- HUD, DOSSIER & INSTRUMENT READOUTS ---
	"OBJ_HEADER": {
		"ru": "Замки шлюза: %d/4",
		"en": "Airlock locks: %d/4"
	},
	"OBJ_PLANKS": {
		"ru": "Доски (монтировка)",
		"en": "Planks (crowbar)"
	},
	"OBJ_CABLE": {
		"ru": "Силовой кабель (болторез)",
		"en": "Power cable (bolt cutters)"
	},
	"OBJ_POWER": {
		"ru": "Энергоблок (предохранитель)",
		"en": "Power unit (fuse)"
	},
	"OBJ_PADLOCK": {
		"ru": "Замок (ключ из сейфа)",
		"en": "Padlock (master key in safe)"
	},
	"OBJ_OPEN_EXIT": {
		"ru": "Все замки сняты. Откройте северный шлюз.",
		"en": "All locks cleared. Open the north gate."
	},
	"DOSSIER_BTN": {
		"ru": "Досье [%d/4]",
		"en": "Dossier [%d/4]"
	},
	"DOSSIER_HINT_KEY": {
		"ru": "Нажмите «Досье» снова, чтобы скрыть",
		"en": "Tap Dossier again to hide"
	},
	"RADAR_RECON": {
		"ru": "РАЗВЕДКА",
		"en": "RECON"
	},
	"RADAR_COOP": {
		"ru": "КАНАЛ %s",
		"en": "CH %s"
	},
	"ACOUSTIC_TAG": {
		"ru": "ШУМ",
		"en": "NOISE"
	},
	"ACOUSTIC_HOLD": {
		"ru": "ТИХО",
		"en": "HOLD"
	},
	"VITALS_HEALTHY": {
		"ru": "В норме",
		"en": "Stable"
	},
	"VITALS_WOUNDED": {
		"ru": "Ранен",
		"en": "Wounded"
	},
	"VITALS_CAGED": {
		"ru": "В клетке",
		"en": "Caged"
	},
	"BREATH_HOLDING": {
		"ru": "Задержка дыхания",
		"en": "Holding breath"
	},
	"POSTURE_STAND": {
		"ru": "Стоя",
		"en": "Standing"
	},
	"POSTURE_CROUCH": {
		"ru": "Присев",
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
	"STATUS_ECHOLOCATE": {
		"ru": "Сонар Слухача-07. Замрите или не дышите.",
		"en": "Sonar pulse. Freeze or hold breath."
	},
	"STATUS_SNIFFING": {
		"ru": "Он у двери шкафа. Задержите дыхание.",
		"en": "It's right outside. Hold your breath."
	},
	"STATUS_STUNNED": {
		"ru": "Слухач-07 оглушён",
		"en": "Listener-07 stunned"
	},
	"STATUS_ALERT": {
		"ru": "Слухач-07 идёт на шум",
		"en": "Listener-07 heard a noise"
	},
	"STATUS_CHASE": {
		"ru": "Погоня. Скройтесь из виду.",
		"en": "Run. Break sight and hide."
	},
	"STATUS_HIDING": {
		"ru": "В шкафу. Не шумите.",
		"en": "In locker. Stay quiet."
	},
	"STATUS_DOWNED": {
		"ru": "Вы ранены. Ползите в укрытие или ждите помощи (%d с)",
		"en": "Downed. Crawl to cover or wait for help (%ds)"
	},
	"STATUS_ALLY_DOWN": {
		"ru": "%s ранен, метка на радаре.",
		"en": "%s is down. Check radar."
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
		"ru": "Предохранитель",
		"en": "Power fuse"
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
		"ru": "Стеклянная бутылка",
		"en": "Glass bottle"
	},
	"ITEM_syringe": {
		"ru": "Адреналин",
		"en": "Adrenaline shot"
	},
	"ITEM_battery": {
		"ru": "Батарея",
		"en": "Battery"
	},
	"ITEM_flare": {
		"ru": "Фальшфейер",
		"en": "Stun flare"
	},
	"ITEM_medkit": {
		"ru": "Аптечка",
		"en": "Medkit"
	},
	"ITEM_screwdriver": {
		"ru": "Отвёртка",
		"en": "Screwdriver"
	},
	# --- INTERACTION PROMPTS ---
	"PROMPT_TAKE": {
		"ru": "Взять: %s",
		"en": "Take: %s"
	},
	"PROMPT_INV_FULL": {
		"ru": "Нет места. Выбросьте предмет.",
		"en": "Hands full. Drop something first."
	},
	"PROMPT_DOOR_OPEN": {
		"ru": "Открыть дверь",
		"en": "Open door"
	},
	"PROMPT_DOOR_CLOSE": {
		"ru": "Закрыть дверь",
		"en": "Close door"
	},
	"PROMPT_HIDE_LOCKER": {
		"ru": "Спрятаться в шкафу",
		"en": "Hide in locker"
	},
	"PROMPT_EXIT_LOCKER": {
		"ru": "Выйти из шкафа",
		"en": "Leave locker"
	},
	"PROMPT_SEARCH_DRAWER": {
		"ru": "Обыскать ящик",
		"en": "Search drawer"
	},
	"PROMPT_VENT_UNSCREW": {
		"ru": "Открутить решётку (тихо)",
		"en": "Unscrew vent (quiet)"
	},
	"PROMPT_VENT_FORCE": {
		"ru": "Выломать решётку (шумно)",
		"en": "Rip open vent (loud)"
	},
	"PROMPT_PA_LURE": {
		"ru": "Включить сирену в другом крыле",
		"en": "Sound distant siren"
	},
	"PROMPT_PA_COOLDOWN": {
		"ru": "Сирена на паузе (%d с)",
		"en": "Intercom recharging (%ds)"
	},
	"PROMPT_CAGE_UNLOCK": {
		"ru": "Открыть засов",
		"en": "Open cage latch"
	},
	"PROMPT_SELF_REVIVE": {
		"ru": "Вколоть адреналин",
		"en": "Use adrenaline to get up"
	},
	"PROMPT_SAFE_ENTER": {
		"ru": "Открыть сейф",
		"en": "Enter safe code"
	},
	"PROMPT_SAFE_OPENED": {
		"ru": "Сейф открыт",
		"en": "Safe open"
	},
	"PROMPT_GEN_NEED_FUSE": {
		"ru": "Нет питания. Нужен предохранитель.",
		"en": "No power. Needs a fuse."
	},
	"PROMPT_GEN_INSERT": {
		"ru": "Вставить предохранитель",
		"en": "Insert fuse"
	},
	"PROMPT_GEN_ONLINE": {
		"ru": "Питание подано",
		"en": "Power on"
	},
	"PROMPT_EXIT_PRY": {
		"ru": "Оторвать доски",
		"en": "Pry off planks"
	},
	"PROMPT_EXIT_CUT": {
		"ru": "Перекусить кабель",
		"en": "Cut power cable"
	},
	"PROMPT_EXIT_UNLOCK": {
		"ru": "Открыть замок",
		"en": "Unlock padlock"
	},
	"PROMPT_EXIT_ESCAPE": {
		"ru": "Открыть шлюз и выйти",
		"en": "Open airlock and escape"
	},
	"PROMPT_EXIT_LOCKED": {
		"ru": "Шлюз закрыт (осталось: %d)",
		"en": "Airlock locked (%d left)"
	},
	"PROMPT_REVIVE_ALLY": {
		"ru": "Поднять: %s",
		"en": "Help %s up"
	},
	# --- MODALS & ENDINGS ---
	"SAFE_MODAL_TITLE": {
		"ru": "Кодовый замок",
		"en": "Safe keypad"
	},
	"SAFE_KNOWN_CODE": {
		"ru": "Код: %s",
		"en": "Code: %s"
	},
	"SAFE_NO_NOTE": {
		"ru": "Код неизвестен. Ищите в столах и шкафах.",
		"en": "Code unknown. Search desks and cabinets."
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
		"ru": "Начать заново",
		"en": "Restart"
	},
	"PAUSE_MAIN_MENU": {
		"ru": "В меню",
		"en": "Main menu"
	},
	"CAGE_TRANSITION_TITLE": {
		"ru": "Клетка в Хирургии",
		"en": "Surgery holding cage"
	},
	"CAGE_TRANSITION_SUB": {
		"ru": "Слухач-07 запер вас в клетке. Вещи остались при вас. Откройте засов, когда шаги стихнут, и найдите аптечку.",
		"en": "Listener-07 dragged you into the Surgery cage. Your gear is still on you. Open the latch once it leaves and find a medkit."
	},
	"VICTORY_TITLE": {
		"ru": "Вы выбрались",
		"en": "You escaped"
	},
	"VICTORY_STATS": {
		"ru": "Северный шлюз открыт  ·  Время: %s",
		"en": "North airlock cleared  ·  Time: %s"
	},
	"GAMEOVER_TITLE": {
		"ru": "Вы не выбрались",
		"en": "You didn't make it"
	},
	"GAMEOVER_SUB": {
		"ru": "Вы погибли в НИИ-07.",
		"en": "You died inside NII-07."
	},
	"TOAST_SYRINGE_USED": {
		"ru": "Адреналин: 10 секунд бега без шума",
		"en": "Adrenaline shot: silent sprint for 10s"
	},
	"TOAST_MEDKIT_USED": {
		"ru": "Раны перевязаны",
		"en": "Wounds patched up"
	},
	"TOAST_FLARE_USED": {
		"ru": "Фальшфейер пошёл. Он оглушит Слухача-07.",
		"en": "Flare out. It will stun Listener-07."
	},
	"TOAST_BATTERY_USED": {
		"ru": "Батарея заменена",
		"en": "Fresh battery loaded"
	},
	"TOAST_CODE_FOUND": {
		"ru": "Код сейфа записан: %s",
		"en": "Safe code saved: %s"
	},
	"TOAST_PA_TRIGGERED": {
		"ru": "Сирена орёт в секторе «%s». Слухач-07 идёт туда.",
		"en": "Siren active in %s. Monster heading there."
	},
	"TOAST_GASP": {
		"ru": "Воздух кончился, вы громко вдохнули.",
		"en": "Out of breath. You gasped loudly."
	},
	"TOAST_MP_SYNC": {
		"ru": "Подключено к игре хоста",
		"en": "Connected to host"
	},
	"COOP_RELAY_HINT": {
		"ru": "Через интернет: wss:// адрес хоста. По одной Wi-Fi сети: ws://IP-хоста:8787",
		"en": "Online: host's wss:// address. Same Wi-Fi: ws://HOST-IP:8787"
	},
	"COOP_STATUS_CONNECTING": {
		"ru": "Подключаемся к серверу...",
		"en": "Connecting..."
	},
	"COOP_STATUS_CONNECTED": {
		"ru": "Связь есть. Создайте комнату или введите код.",
		"en": "Connected. Create a room or enter a code."
	},
	"COOP_ERR_NOT_FOUND": {
		"ru": "Комната не найдена. Проверьте код из 4 букв.",
		"en": "Room not found. Check the 4-letter code."
	},
	"COOP_ERR_FULL": {
		"ru": "Комната заполнена (4/4)",
		"en": "Room full (4/4)"
	},
	"COOP_ERR_UNREACHABLE": {
		"ru": "Сервер не отвечает. Проверьте, запущен ли он.",
		"en": "Can't reach server. Make sure it's running."
	},
	"COOP_ERR_GENERIC": {
		"ru": "Ошибка сервера: %s",
		"en": "Server error: %s"
	},
	# --- FIELD ORIENTATION TUTORIAL ---
	"TUT_HEADER": {
		"ru": "Подсказки",
		"en": "Basics"
	},
	"TUT_SKIP": {
		"ru": "Пропустить",
		"en": "Skip"
	},
	"TUT_NEXT": {
		"ru": "Дальше",
		"en": "Next"
	},
	"TUT_DONE": {
		"ru": "Понятно",
		"en": "Got it"
	},
	"TUT_STEP_1": {
		"ru": "Ходите на WASD, приседайте на C. Бег слышно далеко по коридорам.",
		"en": "Move with WASD and press C to crouch. Running echoes down the halls."
	},
	"TUT_STEP_2": {
		"ru": "Включите фонарь на F и подберите инструмент на E впереди, в палате Б-04.",
		"en": "Press F for your flashlight and E to grab the tool ahead in Ward B-04."
	},
	"TUT_STEP_3": {
		"ru": "Удерживайте Пробел, чтобы не дышать, когда Слухач-07 пускает сонар или проверяет шкаф.",
		"en": "Hold Space to hold your breath when Listener-07 clicks nearby or checks your locker."
	},
	"TUT_STEP_4": {
		"ru": "Откройте досье на Tab. Снимите 4 замка с Северного шлюза, таймера нет.",
		"en": "Press Tab to open your Dossier. Clear all 4 North Airlock locks to get out."
	},
	"TUT_STEP_1_TOUCH": {
		"ru": "Двигайтесь левым стиком (до края для бега). Кнопка приседа справа делает шаги тише.",
		"en": "Use the left stick to move (push to the edge to run) and tap Crouch to stay quiet."
	},
	"TUT_STEP_2_TOUCH": {
		"ru": "Нажмите фонарь справа и дважды коснитесь правой части экрана, чтобы взять инструмент в палате Б-04.",
		"en": "Tap Flashlight on the right, then double-tap the right side of the screen to grab the tool in Ward B-04."
	},
	"TUT_STEP_3_TOUCH": {
		"ru": "Удерживайте кнопку лёгких справа, когда Слухач-07 проверяет комнату или шкаф.",
		"en": "Hold the Lungs button when Listener-07 scans the room or checks your locker."
	},
	"TUT_STEP_4_TOUCH": {
		"ru": "Нажмите «Досье» вверху слева. Снимите 4 замка с Северного шлюза, таймера нет.",
		"en": "Tap Dossier at top-left. Clear all 4 North Airlock locks to get out."
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
