# Outline Server

Внутреннее имя для сервера Outline - «Shadowbox». Это сервер настроен
который запускает API управления пользователями и запускает экземпляры Shadowsocks по требованию.

Он призван максимально упростить настройку Shadowsocks и обмен ими
сервер. Он управляется Outline Manager и используется в качестве прокси-сервера Outline.
клиентские приложения. Shadowbox также совместим со стандартными клиентами Shadowsocks.

## Self-hosted installation

Чтобы установить и запустить Shadowbox на вашем собственном сервере, запустите
```
sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/Jigsaw-Code/outline-server/master/src/server_manager/install_scripts/install_server.sh)"
```

использовать `sudo --preserve-env` если вам нужно передать переменные среды. использование `bash -x` если вам нужно отладить установку.

## Запуск из исходного кода

### Предпосылки

кроме [Node](https://nodejs.org/en/download/) и [Yarn](https://yarnpkg.com/en/docs/install), вам также понадобится:

1. [Docker 1.13+](https://docs.docker.com/engine/installation/)
1. [docker-compose 1.11+](https://docs.docker.com/compose/install/)

### Запуск Shadowbox как Node.js app

> **NOTE:**: Это в настоящее время сломано. Вместо этого используйте опцию докера.

Build and run the server as a Node.js app:
```
yarn do shadowbox/server/run
```
The output will be at `build/shadowbox/app`.

### Запуск Shadowbox в качестве Docker-контейнера

> **NOTE**: В настоящее время это не работает в Docker на Mac из-за использования
`--network=host` и проверки целостности не пройдены. А пока смотрите руководство
раздел тестирования ниже.

### С помощью команды docker

Построить образ и запустить сервер:
```
yarn do shadowbox/docker/run
```

Вы должны быть в состоянии успешно запросить API управления:
```
curl --insecure https://[::]:8081/TestApiPrefix/server
```

Чтобы построить только изображение:
```
yarn do shadowbox/docker/build
```

Debug image:
```
docker run --rm -it --entrypoint=sh outline/shadowbox
```

Or a running container:
```
docker exec -it shadowbox sh
```

Delete dangling images:
```
docker rmi $(docker images -f dangling=true -q)
```


## Access Keys Management API

In order to utilize the Management API, you'll need to know the apiUrl for your Outline server.
You can obtain this information from the "Settings" tab of the server page in the Outline Manager.
Alternatively, you can check the 'access.txt' file under the '/opt/outline' directory of an Outline server. An example apiUrl is: https://1.2.3.4:1234/3pQ4jf6qSr5WVeMO0XOo4z. 

See [Full API Documentation](https://rebilly.github.io/ReDoc/?url=https://raw.githubusercontent.com/Jigsaw-Code/outline-server/master/src/shadowbox/server/api.yml).
The OpenAPI specification can be found at [api.yml](./api.yml).

### Examples

Start by storing the apiURL you see see in that file, as a variable. For example:
```
API_URL=https://1.2.3.4:1234/3pQ4jf6qSr5WVeMO0XOo4z
```

You can then perform the following operations on the server, remotely.

List access keys
```
curl --insecure $API_URL/access-keys/
```

Create an access key
```
curl --insecure -X POST $API_URL/access-keys
```

Rename an access key
(e.g. rename access key 2 to 'albion')
```
curl --insecure -X PUT curl -F 'name=albion' $API_URL/access-keys/2/name
```

Remove an access key
(e.g. remove access key 2)
```
curl --insecure -X DELETE $API_URL/access-keys/2
```

## Testing

### Manual

After building a docker image with some local changes,
upload it to your favorite registry
(e.g. Docker Hub, quay.io, etc.).

Then set your `SB_IMAGE` environment variable to point to the image you just
uploaded (e.g. `export SB_IMAGE=yourdockerhubusername/shadowbox`) and
run `yarn do server_manager/electron_app/run` and your droplet should be created with your
modified image.

### Automated

To run the integration test:
```
yarn do shadowbox/integration_test/run
```

This will set up three containers and two networks:
```
client <-> shadowbox <-> target
```

`client` can only access `target` via shadowbox. We create a user on `shadowbox` then connect using the Shadowsocks client.

To test clients that rely on fetching a docker image from Dockerhub, you can push an image to your account and modify the
client to use your image. To push your own image:
```
yarn shadowbox_docker_build && docker tag quay.io/outline/shadowbox $USER/shadowbox && docker push $USER/shadowbox
```

If you need to test an unsigned image (e.g. your dev one):
```
DOCKER_CONTENT_TRUST=0 SHADOWBOX_IMAGE=$USER/shadowbox yarn do shadowbox/integration_test/run
```

You can add tags if you need different versions in different clients.
