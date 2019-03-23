#!/usr/bin/env bash
# Copyright 2018 The Outline Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Скрипт для установки docker-контейнера shadowbox, docker-контейнера сторожевой башни
# (для автоматического обновления shadowbox) и для создания нового пользователя shadowbox.

# Вы можете установить следующие переменные окружения, переопределяя их значения по умолчанию:
# SB_IMAGE: Образ Shadowbox Docker для установки, например quay.io/outline/shadowbox:nightly
# SB_API_PORT: Номер порта API управления.
# SHADOWBOX_DIR: Каталог для постоянного состояния Shadowbox.
# SB_PUBLIC_IP: Публичный IP-адрес для Shadowbox.
# ACCESS_CONFIG: Расположение текстового файла конфигурации доступа.
# SB_DEFAULT_SERVER_NAME: Имя по умолчанию для этого сервера, например "Набросок сервера Нью-Йорк".
#     Это имя будет использоваться для сервера, пока администраторы не обновят имя
# через REST API.
# SENTRY_LOG_FILE: Файл для записи логов, которые могут быть переданы в Sentry, в случае
# ошибки установки. Никакой PII не должен быть записан в этот файл. Предназначен для установки
# только от do_install_server.sh.
# WATCHTOWER_REFRESH_SECONDS: интервал обновления в секундах для проверки обновлений,
# по умолчанию 3600.

# Требуется установить curl и докер

set -euo pipefail

readonly SENTRY_LOG_FILE=${SENTRY_LOG_FILE:-}



function log_error() {
  local -r ERROR_TEXT="\033[0;31m"  # red
  local -r NO_COLOR="\033[0m"
  >&2 printf "${ERROR_TEXT}${1}${NO_COLOR}\n"
}

# Довольно печатает текст на стандартный вывод, а также записывает в файл журнала часового, если установлен.
function log_start_step() {
  log_for_sentry "$@"
  str="> $@"
  lineLength=47
  echo -n "$str"
  numDots=$(expr $lineLength - ${#str} - 1)
  if [[ $numDots > 0 ]]; then
    echo -n " "
    for i in $(seq 1 "$numDots"); do echo -n .; done
  fi
  echo -n " "
}

# Запуск отслеживания шагов
function run_step() {
  local -r msg=$1
  log_start_step $msg
  shift 1
  if "$@"; then
    echo "OK"
  else
    # Распространяет код ошибки
    return
  fi
}


function confirm() {
  echo -n "$1"
  local RESPONSE
  read RESPONSE
  RESPONSE=$(echo "$RESPONSE" | tr '[A-Z]' '[a-z]')
  if [[ -z "$RESPONSE" ]] || [[ "$RESPONSE" = "y" ]] || [[ "$RESPONSE" = "yes" ]]; then
    return 0
  fi
  return 1
}


function command_exists {
  command -v "$@" > /dev/null 2>&1
}

function log_for_sentry() {
  if [[ -n "$SENTRY_LOG_FILE" ]]; then
    echo [$(date "+%Y-%m-%d@%H:%M:%S")] "install_server.sh" "$@" >>$SENTRY_LOG_FILE
  fi
}

# Проверьте, установлен ли докер.
function verify_docker_installed() {
  if command_exists docker; then
    return 0
  fi
  log_error "NOT INSTALLED"
  echo -n
  if ! confirm "> Would you like to install Docker? This will run 'curl -sS https://get.docker.com/ | sh'. [Y/n] "; then
    exit 0
  fi
  if ! run_step "Installing Docker" install_docker; then
    log_error "Docker installation failed, please visit https://docs.docker.com/install for instructions."
    exit 1
  fi
  echo -n "> Verifying Docker installation................ "
  command_exists docker
}

# Проверяет запущен ли докер
function verify_docker_running() {
  local readonly STDERR_OUTPUT
  STDERR_OUTPUT=$(docker info 2>&1 >/dev/null)
  local readonly RET=$?
  if [[ $RET -eq 0 ]]; then
    return 0
  elif [[ $STDERR_OUTPUT = *"Is the docker daemon running"* ]]; then
    start_docker
  fi
}

# Устанавливает докер
function install_docker() {
  curl -sS https://get.docker.com/ | sh > /dev/null 2>&1
}

function start_docker() {
  systemctl start docker.service > /dev/null 2>&1
  systemctl enable docker.service > /dev/null 2>&1
}

function docker_container_exists() {
  docker ps | grep $1 >/dev/null 2>&1
}

function remove_shadowbox_container() {
  remove_docker_container shadowbox
}

function remove_watchtower_container() {
  remove_docker_container watchtower
}

function remove_docker_container() {
  docker rm -f $1 > /dev/null
}

function handle_docker_container_conflict() {
  local readonly CONTAINER_NAME=$1
  local readonly EXIT_ON_NEGATIVE_USER_RESPONSE=$2
  local PROMPT="> Название контейнера \"$CONTAINER_NAME\" уже используется другим контейнером. Это может произойти при многократном запуске этого скрипта."
  if $EXIT_ON_NEGATIVE_USER_RESPONSE; then
    PROMPT="$PROMPT Мы попытаемся удалить существующий контейнер и перезапустить его. Хотите продолжить? [Y/n] "
  else
    PROMPT="$PROMPT Хотите заменить этот контейнер? Если вы ответите «нет», мы продолжим установку. [Y/n] "
  fi
  if ! confirm "$PROMPT"; then
    if $EXIT_ON_NEGATIVE_USER_RESPONSE; then
      exit 0
    fi
    return 0
  fi
  if run_step "Удалять $CONTAINER_NAME контейнер" remove_"$CONTAINER_NAME"_container ; then
    echo -n "> Перезагружать $CONTAINER_NAME ........................ "
    start_"$CONTAINER_NAME"
    return $?
  fi
  return 1
}

# Установить ловушку, которая публикует тег ошибки только в случае ошибки.
function finish {
  EXIT_CODE=$?
  if [[ $EXIT_CODE -ne 0 ]]
  then
    log_error "\nСожалею! Что-то пошло не так. Если вы не можете понять это, пожалуйста, скопируйте и вставьте весь этот вывод в экран Outline Manager и отправьте его нам, чтобы узнать, можем ли мы вам помочь.."
  fi
}
trap finish EXIT

function get_random_port {
  local num=0  # Init к недопустимому значению, чтобы предотвратить ошибки "unbound variable".
  until (( 1024 <= num && num < 65536)); do
    num=$(( $RANDOM + ($RANDOM % 2) * 32768 ));
  done;
  echo $num;
}

function create_persisted_state_dir() {
  readonly STATE_DIR="$SHADOWBOX_DIR/persisted-state"
  mkdir -p --mode=770 "${STATE_DIR}"
  chmod g+s "${STATE_DIR}"
}

# Сгенерируйте секретный ключ для доступа к API shadowbox и сохраните его в теге..
# 16 bytes = 128 bits энтропии должно быть много для этого использования.
function safe_base64() {
  # Реализует URL-безопасный base64 из stdin, раздевание trailing = chars.
  # Записывает результат в стандартный вывод.
  # TODO: this gives the following errors on Mac:
  #   base64: invalid option -- w
  #   tr: illegal option -- -
  local url_safe="$(base64 -w 0 - | tr '/+' '_-')"
  echo -n "${url_safe%%=*}"  # Strip trailing = chars
}

function generate_secret_key() {
  readonly SB_API_PREFIX=$(head -c 16 /dev/urandom | safe_base64)
}

function generate_certificate() {
  # Создайте самоподписанный сертификат и сохраните его в каталоге постоянного состояния.
  readonly CERTIFICATE_NAME="${STATE_DIR}/shadowbox-selfsigned"
  readonly SB_CERTIFICATE_FILE="${CERTIFICATE_NAME}.crt"
  readonly SB_PRIVATE_KEY_FILE="${CERTIFICATE_NAME}.key"
  declare -a openssl_req_flags=(
    -x509 -nodes -days 36500 -newkey rsa:2048
    -subj "/CN=${SB_PUBLIC_IP}"
    -keyout "${SB_PRIVATE_KEY_FILE}" -out "${SB_CERTIFICATE_FILE}"
  )
  openssl req "${openssl_req_flags[@]}" >/dev/null 2>&1
}

function generate_certificate_fingerprint() {
  # Добавьте тег с отпечатком SHA-256 сертификата.
  # (Electron uses SHA-256 fingerprints: https://github.com/electron/electron/blob/9624bc140353b3771bd07c55371f6db65fd1b67e/atom/common/native_mate_converters/net_converter.cc#L60)
  # Example format: "SHA256 Fingerprint=BD:DB:C9:A4:39:5C:B3:4E:6E:CF:18:43:61:9F:07:A2:09:07:37:35:63:67"
  CERT_OPENSSL_FINGERPRINT=$(openssl x509 -in "${SB_CERTIFICATE_FILE}" -noout -sha256 -fingerprint)
  # Example format: "BDDBC9A4395CB34E6ECF1843619F07A2090737356367"
  CERT_HEX_FINGERPRINT=$(echo ${CERT_OPENSSL_FINGERPRINT#*=} | tr --delete :)
  output_config "certSha256:$CERT_HEX_FINGERPRINT"
}

# ЗАПУСК SHADOWBOX
function start_shadowbox() {
  declare -a docker_shadowbox_flags=(
    --name shadowbox --restart=always --net=host
    -v "${STATE_DIR}:${STATE_DIR}"
    -e "SB_STATE_DIR=${STATE_DIR}"
    -e "SB_PUBLIC_IP=${SB_PUBLIC_IP}"
    -e "SB_API_PORT=${SB_API_PORT}"
    -e "SB_API_PREFIX=${SB_API_PREFIX}"
    -e "SB_CERTIFICATE_FILE=${SB_CERTIFICATE_FILE}"
    -e "SB_PRIVATE_KEY_FILE=${SB_PRIVATE_KEY_FILE}"
    -e "SB_METRICS_URL=${SB_METRICS_URL:-}"
    -e "SB_DEFAULT_SERVER_NAME=${SB_DEFAULT_SERVER_NAME:-}"
  )
  # Сам по себе локальный портит код возврата.
  local readonly STDERR_OUTPUT
  STDERR_OUTPUT=$(docker run -d "${docker_shadowbox_flags[@]}" ${SB_IMAGE} 2>&1 >/dev/null)
  local readonly RET=$?
  if [[ $RET -eq 0 ]]; then
    return 0
  fi
  log_error "FAILED"
  if docker_container_exists shadowbox; then
    handle_docker_container_conflict shadowbox true
  else
    log_error "$STDERR_OUTPUT"
    return 1
  fi
}

function start_watchtower() {
  # Запустите сторожевую башню для автоматической загрузки обновлений образа докера.
  # Установите сторожевую башню для обновления каждые 30 секунд, если используется пользовательский SB_IMAGE (для
  # тестирование). В противном случае обновлять каждый час.
  local WATCHTOWER_REFRESH_SECONDS="${WATCHTOWER_REFRESH_SECONDS:-3600}"
  declare -a docker_watchtower_flags=(--name watchtower --restart=always)
  docker_watchtower_flags+=(-v /var/run/docker.sock:/var/run/docker.sock)
  # Сам по себе локальный портит код возврата.
  local readonly STDERR_OUTPUT
  STDERR_OUTPUT=$(docker run -d "${docker_watchtower_flags[@]}" v2tec/watchtower --cleanup --tlsverify --interval $WATCHTOWER_REFRESH_SECONDS 2>&1 >/dev/null)
  local readonly RET=$?
  if [[ $RET -eq 0 ]]; then
    return 0
  fi
  log_error "FAILED"
  if docker_container_exists watchtower; then
    handle_docker_container_conflict watchtower false
  else
    log_error "$STDERR_OUTPUT"
    return 1
  fi
}

# Ждет Shadowbox, чтобы быть здоровым
function wait_shadowbox() {
  # Мы используем небезопасное соединение, потому что наша модель угроз не включает локальный порт
  # перехват и наш сертификат не имеет localhost в качестве альтернативного имени субъекта
  until curl --insecure -s "${LOCAL_API_URL}/access-keys" >/dev/null; do sleep 1; done
}

function create_first_user() {
  curl --insecure -X POST -s "${LOCAL_API_URL}/access-keys" >/dev/null
}

function output_config() {
  echo "$@" >> $ACCESS_CONFIG
}

function add_api_url_to_config() {
  output_config "apiUrl:${PUBLIC_API_URL}"
}

function check_firewall() {
  local readonly ACCESS_KEY_PORT=$(curl --insecure -s ${LOCAL_API_URL}/access-keys |
      docker exec -i shadowbox node -e '
          const fs = require("fs");
          const accessKeys = JSON.parse(fs.readFileSync(0, {encoding: "utf-8"}));
          console.log(accessKeys["accessKeys"][0]["port"]);
      ')
  if ! curl --max-time 5 --cacert "${SB_CERTIFICATE_FILE}" -s "${PUBLIC_API_URL}/access-keys" >/dev/null; then
     log_error "BLOCKED"
     FIREWALL_STATUS="\
Вы не сможете получить к нему внешний доступ, несмотря на то, что ваш сервер работает правильно
настроить, потому что есть брандмауэр (в этой машине, ваш маршрутизатор или облако
провайдер), который предотвращает входящие соединения с портами ${SB_API_PORT} and ${ACCESS_KEY_PORT}."
  else
    FIREWALL_STATUS="\
Если у вас есть проблемы с подключением, возможно, ваш маршрутизатор или облачный провайдер
блокирует входящие соединения, хотя ваша машина, кажется, позволяет им."
  fi
  FIREWALL_STATUS="\
$FIREWALL_STATUS

Make sure to open the following ports on your firewall, router or cloud provider:
- Management port ${SB_API_PORT}, for TCP
- Access key port ${ACCESS_KEY_PORT}, for TCP and UDP
"
}

install_shadowbox() {
  # Убедитесь, что мы не пропускаем читаемые файлы другим пользователям.
  umask 0007

  run_step "Проверка того, что Docker установлен" verify_docker_installed
  run_step "Проверка того, что демон Docker запущен" verify_docker_running

  log_for_sentry "Создание каталога Outline"
  export SHADOWBOX_DIR="${SHADOWBOX_DIR:-/opt/outline}"
  mkdir -p --mode=770 $SHADOWBOX_DIR
  chmod u+s $SHADOWBOX_DIR

  log_for_sentry "Настройка порта API"
  readonly SB_API_PORT="${SB_API_PORT:-$(get_random_port)}"
  readonly ACCESS_CONFIG=${ACCESS_CONFIG:-$SHADOWBOX_DIR/access.txt}
  readonly SB_IMAGE=${SB_IMAGE:-vo0doo/shadowbox}

  log_for_sentry "Настройка SB_PUBLIC_IP"
  # TODO(fortuna): Make sure this is IPv4
  readonly SB_PUBLIC_IP=${SB_PUBLIC_IP:-$(curl -4s https://ipinfo.io/ip)}

  if [[ -z $SB_PUBLIC_IP ]]; then
    local readonly MSG="Не удалось определить IP-адрес сервера."
    log_error "$MSG"
    log_for_sentry "$MSG"
    exit 1
  fi

  # Если $ACCESS_CONFIG уже существует, скопируйте его в резервную копию и очистите его.
  # Обратите внимание, что здесь мы не можем сделать "mv", так как do_install_server.sh может быть уже в хвосте
  # этот файл.
  log_for_sentry "Initializing ACCESS_CONFIG"
  [[ -f $ACCESS_CONFIG ]] && cp $ACCESS_CONFIG $ACCESS_CONFIG.bak && > $ACCESS_CONFIG

  # Сделать каталог для постоянного состояния
  run_step "Creating persistent state dir" create_persisted_state_dir
  run_step "Generating secret key" generate_secret_key
  run_step "Generating TLS certificate" generate_certificate
  run_step "Generating SHA-256 certificate fingerprint" generate_certificate_fingerprint
  # TODO(dborkan): если скрипт завершится неудачно после запуска Docker, он продолжит работать
  # поскольку имена shadowbox и watchtower уже будут использоваться. Рассматривать
  # удаление контейнера в случае сбоя (например, использование ловушки или
  # удаление существующих контейнеров при каждом запуске).
  run_step "Запуск Shadowbox" start_shadowbox
  # TODO(fortuna): Не ждите Shadowbox, чтобы запустить это.
  run_step "Запуск Сторожевой Башни" start_watchtower

  readonly PUBLIC_API_URL="https://${SB_PUBLIC_IP}:${SB_API_PORT}/${SB_API_PREFIX}"
  readonly LOCAL_API_URL="https://localhost:${SB_API_PORT}/${SB_API_PREFIX}"
  run_step "В ожидании сервера Outline, чтобы быть здоровым" wait_shadowbox
  run_step "Создание первого пользователя" create_first_user
  run_step "Добавление API URL в конфигурацию" add_api_url_to_config

  FIREWALL_STATUS=""
  run_step "Проверка брандмауэра хоста" check_firewall

  # Выводит значение указанного поля из ACCESS_CONFIG.
  # например если ACCESS_CONFIG содержит строку «certSha256: 1234»,
  # вызов $ (get_field_value certSha256) выдаст эхо 1234.
  function get_field_value {
    grep "$1" $ACCESS_CONFIG | sed "s/$1://"
  }

  # Выходной JSON. Это полагается на apiUrl и certSha256 (шестнадцатеричные символы), требующие
  # строка не экранирована.  TODO: искать способ генерировать JSON, который не
  # требуют новых зависимостей.
  cat <<END_OF_SERVER_OUTPUT

CONGRATULATIONS! Your Outline server is up and running.

To manage your Outline server, please copy the following line (including curly
brackets) into Step 2 of the Outline Manager interface:

$(echo -e "\033[1;32m{\"apiUrl\":\"$(get_field_value apiUrl)\",\"certSha256\":\"$(get_field_value certSha256)\"}\033[0m")

${FIREWALL_STATUS}
END_OF_SERVER_OUTPUT
} # конец install_shadowbox

# Завернут в функцию для некоторой защиты от половинных загрузок.
install_shadowbox
