# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины

- Наименование: `devops-vm`
- Тип гостевой ОС: Ubuntu Server 24.04.4 LTS (64-bit)
- Объём оперативной памяти: 2048 МБ
- Количество ядер процессора: 2
- Объём дискового накопителя: 25 ГБ, динамически расширяемый

## 2. Сетевые интерфейсы

| Адаптер | Тип          | Адрес             | Назначение                                   |
|---------|--------------|-------------------|-----------------------------------------------|
| 1       | NAT          | 10.0.2.15/24      | Доступ ВМ к репозиториям пакетов (интернет)   |
| 2       | Host-only    | 192.168.56.101/24 | Доступ с хостовой системы (SSH, HTTP/HTTPS)   |

## 3. Правило проброса портов

| Имя  | Протокол | Порт хоста | Порт гостя |
|------|----------|------------|------------|
| ssh  | TCP      | 2222       | 2222 (изменён с 22 после hardening SSH, ПР №5 шаг 2.4) |

Адрес хостовой системы: `127.0.0.1`.

## 4. Учётные записи

| Имя      | Группы        | Аутентификация                          |
|----------|---------------|------------------------------------------|
| student  | sudo          | пароль (создана установщиком, не используется для управления) |
| devops   | devops, sudo, docker | только по ключу (`~/.ssh/devops_vm`, ed25519); парольная аутентификация SSH отключена глобально |

## 5. Служба SSH

- Порт: `2222` (нестандартный)
- Файл конфигурации: `/etc/ssh/sshd_config.d/99-hardening.conf`
- Изменённые директивы: `PermitRootLogin no`, `PasswordAuthentication no`, `PubkeyAuthentication yes`, `PermitEmptyPasswords no`, `MaxAuthTries 3`, `LoginGraceTime 30`, `AllowUsers devops`, `X11Forwarding no`, `ClientAliveInterval 300`, `ClientAliveCountMax 2`
- Особенность: файл `/etc/ssh/sshd_config.d/50-cloud-init.conf` (генерируется cloud-init) содержал конфликтующую директиву `PasswordAuthentication yes`; строка закомментирована вручную.
- Служба переведена с активации по сокету (`ssh.socket`) на обычный сервис (`ssh.service`).

## 6. Правила межсетевого экрана

- Политики по умолчанию: `deny incoming`, `allow outgoing`
- Логирование: `on (medium)`
- Правила:

| Порт      | Действие   | Комментарий        |
|-----------|------------|--------------------|
| 2222/tcp  | LIMIT IN   | SSH rate-limited    |
| 80/tcp    | ALLOW IN   | HTTP               |
| 443/tcp   | ALLOW IN   | HTTPS              |

(правила продублированы для IPv6)

## 7. Снимки состояния

| Наименование         | Момент создания (этап)                                   |
|----------------------|------------------------------------------------------------|
| `01-clean-install`   | После установки ОС и обновления пакетов (ПР №5, раздел 3)  |
| `02-keys-configured` | После настройки ключевой аутентификации (ПР №5, задание 1) |
| `03-ssh-hardened`    | После hardening SSH и настройки UFW (ПР №5, задания 2–3)   |
| `04-nginx-https`     | После настройки Nginx и перевода на HTTPS (ПР №6, задание 2) |
| `05-docker-compose`  | После запуска конфигурации «приложение + СУБД» (ПР №7, задание 2) |

## 8. Веб-сервер

- Устанавливаемый пакет: `nginx` (из штатного репозитория Ubuntu, версия 1.24.0)
- Путь к конфигурации ресурса: `/etc/nginx/sites-available/devops-site` (символическая ссылка в `/etc/nginx/sites-enabled/`); стандартный ресурс (`sites-enabled/default`) отключён.
- Каталог ресурса: `/var/www/devops-site`, владелец `devops:devops`, права `755` для каталога, `644` для файлов (модель «владелец пишет, веб-сервер читает»).
- Сертификат: `/etc/ssl/certs/devops.crt`, права `644`, владелец `root`.
- Закрытый ключ: `/etc/ssl/private/devops.key`, права `600`, владелец `root`.
- Команда формирования сертификата:
  ```
  sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/devops.key \
    -out /etc/ssl/certs/devops.crt \
    -subj "/CN=devops.local" \
    -addext "subjectAltName=DNS:devops.local"
  ```
- Срок действия сертификата: 365 дней (с 2026-10-23 по 2027-10-23).
- HTTP (порт 80) перенаправляется на HTTPS (порт 443) кодом 301.

## 9. Контейнеризация

### 9.1 Docker Engine

- Способ установки: официальный репозиторий Docker (`https://download.docker.com/linux/ubuntu`, дистрибутив `noble`, канал `stable`); пакет `docker.io` из репозитория Ubuntu не используется.
- Ключ репозитория: `/etc/apt/keyrings/docker.asc`, источник: `/etc/apt/sources.list.d/docker.list`.
- Установленные пакеты: `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`.
- Версии: Docker Engine `29.9.3`, Docker Compose `v5.7.0`.
- Команды установки:
  ```
  sudo apt-get update && sudo apt-get install -y ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  ```
- Служба `docker` включена в автозапуск (`systemctl is-enabled docker` → `enabled`).

### 9.2 Участники группы docker

| Учётная запись | Обоснование |
|----------------|-------------|
| `devops`       | Управление контейнерами без `sudo`; учётная запись уже имеет право `sudo`, поэтому членство в группе `docker` (эквивалент прав `root`) не расширяет её привилегий |

Команда: `sudo usermod -aG docker devops` (вступает в силу с новой SSH-сессии). Учётные записи без права `sudo` в группу не включаются.

### 9.3 Проект

- Расположение на сервере: `/home/devops/app` (`~/app`), владелец `devops:devops`.
- Исходный код: каталог `app/` репозитория `devops-course-2026` (`Dockerfile`, `app.py`, `requirements.txt`, `.dockerignore`, `docker-compose.yml`, `.env.example`).
- Доставка с хостовой системы: `rsync -avz --delete --exclude=.env app/ devops:app/` (на хостовой системе без `rsync` — tar-поток по SSH во временный каталог с последующим `rsync --delete --exclude=.env` на сервере, см. ПР №6).
- Запуск: `cd ~/app && docker compose up -d --build`.
- Сервисы:

| Сервис | Образ                | Контейнер   | Пользователь процесса | Перезапуск       |
|--------|----------------------|-------------|------------------------|------------------|
| `db`   | `postgres:16-alpine` | `app-db-1`  | `postgres`             | `unless-stopped` |
| `app`  | `devops-app:1.0` (собирается из `Dockerfile`) | `app-app-1` | `app` (uid 999, не `root`) | `unless-stopped` |

- Порядок запуска: `app` запускается после перехода `db` в состояние `healthy` (`depends_on: condition: service_healthy`, проверка `pg_isready` каждые 5 с).
- Сеть: пользовательская сеть `app_backend` (драйвер `bridge`); приложение обращается к СУБД по имени сервиса `db` (переменная `DB_HOST=db`).

### 9.4 Файл переменных окружения

- Расположение: `/home/devops/app/.env`, владелец `devops:devops`, права `600`.
- Формируется только на сервере из шаблона `.env.example`, пароль СУБД генерируется случайно:
  ```
  cd ~/app
  cp .env.example .env
  chmod 600 .env
  sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 16)/" .env
  ```
- Исключён из репозитория (`.gitignore`), из контекста сборки (`app/.dockerignore`) и из доставки (`--exclude=.env`).

### 9.5 Публикуемые порты и адреса

| Сервис | Порт контейнера | Публикация         | Доступ |
|--------|-----------------|--------------------|--------|
| `app`  | 5000/tcp        | `127.0.0.1:5000`   | только с самого сервера (Nginx) |
| `db`   | 5432/tcp        | не публикуется     | только из сети `app_backend` |

Публикация на `0.0.0.0` не допускается: правила iptables, добавляемые Docker, обрабатывают пакет раньше правил UFW, и порт становится доступен из сети независимо от политики межсетевого экрана (раздел 6).

### 9.6 Именованные тома

| Том           | Точка монтирования в контейнере | Расположение на сервере |
|---------------|---------------------------------|--------------------------|
| `app_db_data` | `/var/lib/postgresql/data` (`db`) | `/var/lib/docker/volumes/app_db_data/_data` |

`docker compose down` сохраняет том, `docker compose down -v` удаляет данные СУБД без возможности восстановления. Основная версия СУБД зафиксирована тегом `16-alpine`: формат данных несовместим между основными версиями PostgreSQL.

### 9.7 Обратный прокси-сервер

В блок HTTPS файла `/etc/nginx/sites-available/devops-site` (раздел 8) добавлено расположение, статический ресурс `location /` сохранён:

```
    location /app/ {
        proxy_pass http://127.0.0.1:5000/;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
```

- Применение: `sudo nginx -t && sudo systemctl reload nginx`.
- Завершающий `/` в `proxy_pass` заменяет префикс `/app/` на `/` (`/app/health` → `/health`).
- Адреса: `https://devops.local/app/` (приложение), `https://devops.local/` (статический ресурс).
- При недоступности приложения Nginx возвращает `502 Bad Gateway`, запись в `/var/log/nginx/devops-site.error.log`: `connect() failed (111: Connection refused) while connecting to upstream`.

### 9.8 Проверка

Раздел `[5] Контейнеризация` сценария `scripts/audit.sh`: служба `docker` активна; контейнер `app-db-1` в состоянии `healthy`; порты 5000 и 5432 прослушиваются только на `127.0.0.1`; права `~/app/.env` равны `600`.


## 10. Ansible

### 10.1 Расположение и узлы

- Проект: `ansible/` в репозитории `Rjavuy/devops-course-2026`, ветка `feature/ansible`.
- Управляющий узел (control): хостовая система с Linux/WSL и Ansible 2.16+; коллекции устанавливаются из `ansible/requirements.yml`.
- Управляемый узел (managed): `devops-vm`, Ubuntu Server 24.04 amd64, Host-only адрес `192.168.56.101`, SSH порт 22.
- Модули выполняются на управляемом узле через SSH; постоянный агент не требуется. Коллекции `ansible.posix`, `community.docker`, `community.general` устанавливаются на управляющем узле, а `python3-debian` и `python3-requests` — на управляемом.

### 10.2 Inventory и учётные записи

| Файл | Пользователь | Аутентификация | Когда используется |
|------|--------------|----------------|--------------------|
| `ansible/inventory/bootstrap.ini` | `student` | пароль, `--ask-pass --ask-become-pass` | первичный запуск на чистой VM |
| `ansible/inventory/prod.ini` | `devops` | ключ `~/.ssh/devops_vm` | все последующие запуски и аудит |

Открытый ключ `~/.ssh/devops_vm.pub` читается ролью `ssh`; закрытый ключ хранится только на управляющем узле с правами `0600` и не включается в репозиторий. После установки ключа SSH hardening отключает парольную аутентификацию, поэтому повторный запуск по `student` невозможен и не нужен.

### 10.3 Роли

| Роль | Ответственность |
|------|-----------------|
| `base` | проверка Ubuntu 24.04 amd64, базовые пакеты, официальный репозиторий Docker, Docker Engine |
| `ssh` | пользователь `devops`, SSH-ключ, NOPASSWD sudo, hardening SSH, UFW |
| `nginx` | reverse proxy на порт приложения, отключение default site, `nginx -t` перед reload |
| `app` | загрузка образа по SHA, контейнер с port binding на loopback, проверка `/health` |

`ansible.cfg` содержит `force_handlers = True`: уведомлённые handlers SSH и Nginx выполняются даже при отказе более поздней задачи роли `app`.

### 10.4 Приложение

- Образ: `ghcr.io/rjavuy/devops-ci-app` (публичный пакет из практической работы № 10).
- Тег: полный SHA `7dac688e5bdb14d7568977fdf1080b67731ce354`; `latest` не используется.
- Контейнер: `devops-ci-app`, порт контейнера `5000`, публикация `127.0.0.1:5000:5000`.
- Проверка: `GET http://127.0.0.1:5000/health` → `{"status": "ok"}`; внешний запрос идёт через Nginx `http://192.168.56.101/health`.

### 10.5 Команды

Первичный запуск (интерактивный ввод пароля `student` на два запроса):

```
cd ansible
ansible-playbook -i inventory/bootstrap.ini site.yml --ask-pass --ask-become-pass
```

Проверка перехода на ключ и неинтерактивный доступ:

```
ssh -i ~/.ssh/devops_vm devops@192.168.56.101 "whoami && sudo -n true && echo sudo-ok"
ansible all -m ping
```

Повторный запуск идемпотентного конвейера (ожидается `changed=0`, `failed=0`):

```
cd ansible
ansible-playbook site.yml
```

Read-only аудит из CI (не меняет конфигурацию, ожидается `changed=0`):

```
cd ansible
ansible-playbook verify.yml
```

### 10.6 Адаптация окружения для проверки

На учебном хосте отсутствуют VirtualBox, WSL и локальный Docker, поэтому проверка ролей выполнялась на GitHub-hosted runner `ubuntu-24.04`, который совмещал управляющий и управляемый узлы через SSH-loopback (`127.0.0.1`). Файлы `bootstrap.ini` и `prod.ini` сохранили адрес VM `192.168.56.101`; runner получал адрес через `-e ansible_host=127.0.0.1`. Логи всех запусков и инцидентов загружаются артефактом workflow `.github/workflows/ansible-run.yml`.
