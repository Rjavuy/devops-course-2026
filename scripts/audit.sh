#!/usr/bin/env bash
set -uo pipefail

PASS=0; FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK]   $desc"; ((PASS++))
    else
        echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"; ((FAIL++))
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход от имени root запрещён" "no" "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no" "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"
check "Порт SSH отличен от 22" "yes" "$(sudo sshd -T | awk '/^port/{print ($2 != 22) ? "yes" : "no"}')"
check "MaxAuthTries равен 3" "3" "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"
check "Политика по умолчанию для входящего трафика — deny" "deny" "$(sudo ufw status verbose | awk '/^Default:/{print $2}')"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "  %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер"
check "Служба nginx активна" "active" "$(systemctl is-active nginx)"
sudo nginx -t >/dev/null 2>&1
check "Конфигурация nginx синтаксически корректна" "0" "$?"
openssl x509 -in /etc/ssl/certs/devops.crt -noout -checkend 2592000 >/dev/null 2>&1
check "Сертификат действителен ещё 30+ дней" "0" "$?"
NO_WORLD_WRITABLE="0"
if [[ -n "$(find /var/www/devops-site -perm -o+w 2>/dev/null)" ]]; then
    NO_WORLD_WRITABLE="1"
fi
KEY_MODE="$(sudo stat -c '%a' /etc/ssl/private/devops.key)"
if [[ "$NO_WORLD_WRITABLE" == "0" && "$KEY_MODE" == "600" ]]; then
    WEB_PERMS_OK="0"
else
    WEB_PERMS_OK="1"
fi
check "Нет файлов ресурса, доступных для записи всем, ключ имеет права 600" "0" "$WEB_PERMS_OK"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
