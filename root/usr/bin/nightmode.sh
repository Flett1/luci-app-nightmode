#!/bin/sh

# Постоянное состояние NightMod.
# Наличие файла означает, что LED были выключены NightMod
# и их состояние ещё нужно восстановить.
NIGHT_STATE="/etc/nightmod_saved_leds"

# 1. Чтение настроек UCI из /etc/config/general
LED_OFF=$(uci -q get general.first.button1)
SCHEDULED=$(uci -q get general.second.button2)
START_TIME=$(uci -q get general.second.first_time)
STOP_TIME=$(uci -q get general.second.second_time)


# 2. Проверяем, есть ли для LED собственная UCI-конфигурация
has_uci_led_config() {
	local led_name="$1"

	uci show system 2>/dev/null |
		grep -F ".sysfs='$led_name'" >/dev/null 2>&1
}


# 3. Сохраняем состояние только для LED без UCI-конфигурации
#
# Для LED, настроенных через LuCI/UCI, ничего сохранять не нужно:
# OpenWrt сам знает их trigger/default/delay/etc. и сможет восстановить
# их из /etc/config/system.
save_original_state() {
	# Уже сохранено
	[ -f "$NIGHT_STATE" ] && return

	local tmp_file="${NIGHT_STATE}.tmp"
	local led_dir led_name brightness

	umask 077
	: > "$tmp_file"

	for led_dir in /sys/class/leds/*:status; do
		[ -d "$led_dir" ] || continue
		[ -f "$led_dir/brightness" ] || continue

		led_name="${led_dir##*/}"

		# Если LED настроен через UCI, его состояние восстановит
		# штатный /etc/init.d/led.
		if has_uci_led_config "$led_name"; then
			continue
		fi

		brightness=$(cat "$led_dir/brightness" 2>/dev/null)
		[ -n "$brightness" ] || brightness=0

		echo "$led_name|$brightness" >> "$tmp_file"
	done

	# Создаём файл даже если в нём нет fallback-LED.
	# Сам факт существования файла означает active night state.
	if [ -f "$tmp_file" ]; then
		mv "$tmp_file" "$NIGHT_STATE"
	fi
}


# 4. Полное выключение status LED
turn_off_all() {
	local b_file

	for b_file in /sys/class/leds/*:status/brightness; do
		[ -f "$b_file" ] && echo 0 > "$b_file" 2>/dev/null
	done
}


# 5. Восстановление LED
#
# Сначала штатно применяем UCI-конфигурацию OpenWrt.
# Это возвращает пользовательские trigger/default/delay и т.д.
#
# Затем восстанавливаем brightness только для LED,
# у которых нет UCI-конфигурации.
restore_all() {
	[ -f "$NIGHT_STATE" ] || return

	local led_dir led_name
	local trigger_file
	local restore_ok=1

	# 5.1. Для каждого status LED просим штатный LED-сервис
	# заново применить именно его UCI-конфигурацию.
	for led_dir in /sys/class/leds/*:status; do
		[ -d "$led_dir" ] || continue

		led_name="${led_dir##*/}"
		trigger_file="$led_dir/trigger"

		if has_uci_led_config "$led_name"; then
			if [ -f "$trigger_file" ]; then
				/etc/init.d/led start "$led_name" >/dev/null 2>&1
			fi
		fi
	done

	# 5.2. Восстанавливаем LED без UCI-конфигурации
	if [ -s "$NIGHT_STATE" ]; then
		local saved_led saved_b brightness_file

		while IFS='|' read -r saved_led saved_b; do
			[ -n "$saved_led" ] || continue

			# Если за время ночи для LED появилась UCI-конфигурация,
			# приоритет остаётся за ней.
			if has_uci_led_config "$saved_led"; then
				continue
			fi

			brightness_file="/sys/class/leds/$saved_led/brightness"

			if [ -f "$brightness_file" ]; then
				if ! echo "$saved_b" > "$brightness_file" 2>/dev/null; then
					restore_ok=0
				fi
			fi
		done < "$NIGHT_STATE"
	fi

	# Удаляем состояние только после успешного восстановления.
	if [ "$restore_ok" = "1" ]; then
		rm -f "$NIGHT_STATE"
	fi
}


# 6. Перевод времени HH:MM / HH:MM AM/PM в минуты
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

	# Защита ash от ведущих нулей
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


# 7. Определяем, должен ли сейчас работать ночной режим
SHOULD_OFF=0

# Led Off имеет приоритет над расписанием
if [ "$LED_OFF" = "1" ]; then

	SHOULD_OFF=1

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

	# Расписание внутри одного дня
	if [ "$START_MIN" -le "$STOP_MIN" ]; then

		if [ "$NOW_MIN" -ge "$START_MIN" ] \
			&& [ "$NOW_MIN" -lt "$STOP_MIN" ]; then
			SHOULD_OFF=0
		else
			SHOULD_OFF=1
		fi

	# Расписание через 00:00
	else

		if [ "$NOW_MIN" -ge "$START_MIN" ] \
			|| [ "$NOW_MIN" -lt "$STOP_MIN" ]; then
			SHOULD_OFF=0
		else
			SHOULD_OFF=1
		fi
	fi
fi


# 8. Основное управление
if [ "$SHOULD_OFF" = "1" ]; then

	# Первое включение ночного режима:
	# фиксируем факт сохранения состояния.
	save_original_state

	# Выключаем status LED.
	# На твоём роутере brightness=0 автоматически
	# переводит активный trigger в none.
	turn_off_all

else

	# Ночной режим закончился / Led Off выключен.
	# Возвращаем штатную конфигурацию OpenWrt.
	restore_all

fi
