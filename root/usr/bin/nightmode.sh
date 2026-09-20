#!/bin/sh

# Файл в RAM (/tmp) для хранения исходной яркости светодиодов *:status
SAVED_STATE_FILE="/tmp/led_orig_brightness"

# 1. Чтение настроек UCI из /etc/config/general
LED_OFF=$(uci -q get general.first.button1)
SCHEDULED=$(uci -q get general.second.button2)
START_TIME=$(uci -q get general.second.first_time)
STOP_TIME=$(uci -q get general.second.second_time)

# 2. Запоминаем ТОЧНУЮ исходную яркость (только при первом запуске)
save_original_state() {
	[ -f "$SAVED_STATE_FILE" ] && return

	for led_dir in /sys/class/leds/*:status; do
		if [ -d "$led_dir" ] && [ -f "$led_dir/brightness" ]; then
			local led_name="${led_dir##*/}"
			local orig_b=$(cat "$led_dir/brightness" 2>/dev/null)
			[ -z "$orig_b" ] && orig_b=0

			echo "$led_name $orig_b" >> "$SAVED_STATE_FILE"
		fi
	done
}

# Инициализируем сохранение при старте
save_original_state

# 3. Функции управления яркостью
turn_off_all() {
	for b_file in /sys/class/leds/*:status/brightness; do
		[ -f "$b_file" ] && echo 0 > "$b_file" 2>/dev/null
	done
}

turn_on_all() {
	if [ -f "$SAVED_STATE_FILE" ]; then
		while read -r led_name orig_b; do
			local b_file="/sys/class/leds/$led_name/brightness"
			[ -f "$b_file" ] && echo "$orig_b" > "$b_file" 2>/dev/null
		done < "$SAVED_STATE_FILE"
	fi
}

# 4. Принудительное выключение "Led off"
if [ "$LED_OFF" = "1" ]; then
	turn_off_all
	exit 0
fi

# 5. Перевод времени "HH:MM" или "HH:MM AM/PM" в минуты
time_to_min() {
	local str="$1" period=""

	case "$str" in
		*[Aa][Mm]*) period="AM" ;;
		*[Pp][Mm]*) period="PM" ;;
	esac

	local t="${str%[AaPp][Mm]}"
	t="${t% }"; t="${t# }"

	local h="${t%%:*}"
	local m="${t##*:}"

	# Очистка от ведущих нулей (защита от octal в ash)
	h="${h#0}"; h="${h:-0}"
	m="${m#0}"; m="${m:-0}"

	if [ "$period" = "AM" ]; then
		[ "$h" -eq 12 ] && h=0
	elif [ "$period" = "PM" ]; then
		[ "$h" -lt 12 ] && h=$((h + 12))
	fi

	echo $(( h * 60 + m ))
}

# 6. Проверка работы по расписанию
if [ "$SCHEDULED" = "1" ] && [ -n "$START_TIME" ] && [ -n "$STOP_TIME" ]; then
	set -- $(date +'%H %M')
	NOW_MIN=$(( ${1#0} * 60 + ${2#0} ))

	START_MIN=$(time_to_min "$START_TIME")
	STOP_MIN=$(time_to_min "$STOP_TIME")

	if [ "$START_MIN" -le "$STOP_MIN" ]; then
		# Дневной интервал
		if [ "$NOW_MIN" -ge "$START_MIN" ] && [ "$NOW_MIN" -lt "$STOP_MIN" ]; then
			turn_on_all
		else
			turn_off_all
		fi
	else
		# Ночной интервал с переходом через 00:00
		if [ "$NOW_MIN" -ge "$START_MIN" ] || [ "$NOW_MIN" -lt "$STOP_MIN" ]; then
			turn_on_all
		else
			turn_off_all
		fi
	fi
else
	# Расписание выключено — восстанавливаем состояние
	turn_on_all
fi