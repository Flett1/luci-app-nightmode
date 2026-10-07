#!/bin/sh

# Сохранённое состояние светодиодов NightMod.
# Файл переживает перезагрузку роутера.
NIGHT_STATE="/etc/nightmod_saved_leds"

# 1. Чтение настроек UCI из /etc/config/general
LED_OFF=$(uci -q get general.first.button1)
SCHEDULED=$(uci -q get general.second.button2)
START_TIME=$(uci -q get general.second.first_time)
STOP_TIME=$(uci -q get general.second.second_time)


# 2. Сохраняем исходное состояние LED только один раз.
# Формат:
# имя_LED|brightness|trigger
save_original_state() {
	# Уже сохранено — не перезаписываем.
	[ -f "$NIGHT_STATE" ] && return

	local tmp_file="${NIGHT_STATE}.tmp"
	local led_dir led_name orig_b orig_trigger

	umask 077
	: > "$tmp_file"

	for led_dir in /sys/class/leds/*:status; do
		if [ -d "$led_dir" ] && [ -f "$led_dir/brightness" ]; then

			led_name="${led_dir##*/}"

			orig_b=$(cat "$led_dir/brightness" 2>/dev/null)
			[ -n "$orig_b" ] || orig_b=0

			# Получаем текущий активный trigger.
			orig_trigger=$(sed -n 's/.*\[\([^]]*\)\].*/\1/p' \
				"$led_dir/trigger" 2>/dev/null)

			[ -n "$orig_trigger" ] || orig_trigger="none"

			echo "$led_name|$orig_b|$orig_trigger" >> "$tmp_file"
		fi
	done

	# Если LED не найдены — ничего не сохраняем.
	if [ ! -s "$tmp_file" ]; then
		rm -f "$tmp_file"
		return
	fi

	# Сохраняем состояние.
	mv "$tmp_file" "$NIGHT_STATE"
}


# 3. Выключение всех status LED
turn_off_all() {
	local b_file

	for b_file in /sys/class/leds/*:status/brightness; do
		[ -f "$b_file" ] && echo 0 > "$b_file" 2>/dev/null
	done
}


# 4. Восстановление исходного состояния LED
turn_on_all() {
	[ -f "$NIGHT_STATE" ] || return

	local led_name orig_b orig_trigger
	local b_file trigger_file
	local restore_ok=1

	while IFS='|' read -r led_name orig_b orig_trigger; do
		[ -n "$led_name" ] || continue

		b_file="/sys/class/leds/$led_name/brightness"
		trigger_file="/sys/class/leds/$led_name/trigger"

		# Сначала возвращаем trigger.
		# При brightness=0 он автоматически стал none.
		if [ -f "$trigger_file" ] && [ -n "$orig_trigger" ]; then
			if ! echo "$orig_trigger" > "$trigger_file" 2>/dev/null; then
				restore_ok=0
			fi
		fi

		# Затем возвращаем исходную brightness.
		if [ -f "$b_file" ]; then
			if ! echo "$orig_b" > "$b_file" 2>/dev/null; then
				restore_ok=0
			fi
		fi

	done < "$NIGHT_STATE"

	# Удаляем сохранение только после успешного восстановления.
	if [ "$restore_ok" = "1" ]; then
		rm -f "$NIGHT_STATE"
	fi
}


# 5. Перевод HH:MM / HH:MM AM/PM в минуты
time_to_min() {
	local str="$1"
	local period=""
	local t h m

	case "$str" in
		*[Aa][Mm]*) period="AM" ;;
		*[Pp][Mm]*) period="PM" ;;
	esac

	t="${str%[AaPp][Mm]}"
	t="${t% }"
	t="${t# }"

	h="${t%%:*}"
	m="${t##*:}"

	# Защита ash от ведущих нулей.
	h="${h#0}"
	h="${h:-0}"

	m="${m#0}"
	m="${m:-0}"

	if [ "$period" = "AM" ]; then
		[ "$h" -eq 12 ] && h=0
	elif [ "$period" = "PM" ]; then
		[ "$h" -lt 12 ] && h=$((h + 12))
	fi

	echo $((h * 60 + m))
}


# 6. Определяем, должен ли сейчас работать ночной режим
SHOULD_OFF=0

# Принудительное выключение "Led off"
if [ "$LED_OFF" = "1" ]; then

	SHOULD_OFF=1

# Расписание включено
elif [ "$SCHEDULED" = "1" ] \
	&& [ -n "$START_TIME" ] \
	&& [ -n "$STOP_TIME" ]; then

	set -- $(date +'%H %M')

	NOW_HOUR="${1#0}"
	NOW_HOUR="${NOW_HOUR:-0}"

	NOW_MINUTE="${2#0}"
	NOW_MINUTE="${NOW_MINUTE:-0}"

	NOW_MIN=$((NOW_HOUR * 60 + NOW_MINUTE))

	START_MIN=$(time_to_min "$START_TIME")
	STOP_MIN=$(time_to_min "$STOP_TIME")

	# Интервал внутри одного дня.
	if [ "$START_MIN" -le "$STOP_MIN" ]; then

		if [ "$NOW_MIN" -ge "$START_MIN" ] \
			&& [ "$NOW_MIN" -lt "$STOP_MIN" ]; then
			SHOULD_OFF=0
		else
			SHOULD_OFF=1
		fi

	# Интервал через 00:00.
	else

		if [ "$NOW_MIN" -ge "$START_MIN" ] \
			|| [ "$NOW_MIN" -lt "$STOP_MIN" ]; then
			SHOULD_OFF=0
		else
			SHOULD_OFF=1
		fi
	fi
fi


# 7. Основное управление
if [ "$SHOULD_OFF" = "1" ]; then

	# Если это первый вход в ночной режим,
	# сохраняем то, что было до выключения.
	save_original_state

	# Выключаем LED.
	# На твоём роутере brightness=0 автоматически
	# снимает активный trigger и переводит его в none.
	turn_off_all

else

	# Ночь закончилась или режим выключен.
	# Восстанавливаем brightness и trigger.
	turn_on_all

fi
