#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm.
# Использование: scripts/deploy.sh [--dry-run]
#
# Примечание. На хостовой системе (Windows, Git Bash) бинарник rsync
# недоступен (не установлен ни WSL, ни отдельная сборка — см. отчёт,
# раздел "Затруднения"). Поэтому содержимое передаётся одним SSH-сеансом
# через tar-поток во временный каталог на сервере, а финальная раскладка
# (--delete, --chmod, права) выполняется штатным rsync уже локально на
# самом сервере, где rsync штатно установлен. Семантика и флаги rsync
# идентичны требуемым; открывается ровно одно SSH-соединение.
set -euo pipefail

REMOTE="devops"                      # псевдоним из ~/.ssh/config (ПР № 5, шаг 1.6)
REMOTE_DIR="/var/www/devops-site"
REMOTE_STAGE="/tmp/deploy-stage-$$"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
REPO_ROOT="$(git rev-parse --show-toplevel)"

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
fi

# Требование 4: без главной страницы доставка не выполняется
if [[ ! -f "${REPO_ROOT}/site/index.html" ]]; then
    echo "deploy: ${REPO_ROOT}/site/index.html не найден, доставка отменена" >&2
    exit 1
fi

# Требование 5: в репозитории не должно быть незафиксированных изменений
if [[ -n "$(git -C "${REPO_ROOT}" status --porcelain)" ]]; then
    echo "deploy: в репозитории есть незафиксированные изменения, доставка отменена" >&2
    exit 1
fi

RSYNC_FLAGS="-avz --delete --chmod=D755,F644"
if [[ "${DRY_RUN}" -eq 1 ]]; then
    RSYNC_FLAGS="${RSYNC_FLAGS} --dry-run"
fi

REMOTE_CMD="set -e
rm -rf '${REMOTE_STAGE}'
mkdir -p '${REMOTE_STAGE}'
tar -xzf - -C '${REMOTE_STAGE}'
rsync ${RSYNC_FLAGS} '${REMOTE_STAGE}/site/' '${REMOTE_DIR}/'
rm -rf '${REMOTE_STAGE}'"

# Требования 3 и 8: содержимое передаётся и раскладывается за один SSH-сеанс
tar -czf - -C "${REPO_ROOT}" site | ssh -o BatchMode=yes -o ConnectTimeout=5 "${REMOTE}" "${REMOTE_CMD}"

if [[ "${DRY_RUN}" -eq 1 ]]; then
    exit 0
fi

# Требование 6: проверка доступности с проверкой сертификата (без -k)
if ! curl -f --cacert "${CA_CERT}" -s -o /dev/null "${SITE_URL}"; then
    echo "deploy: ресурс ${SITE_URL} недоступен после доставки" >&2
    exit 1
fi

# Требование 7: успешное завершение — короткий хеш доставленного коммита
git -C "${REPO_ROOT}" rev-parse --short HEAD
exit 0
