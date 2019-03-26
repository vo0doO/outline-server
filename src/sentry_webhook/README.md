# Outline Sentry Webhook

The Outline Sentry webhook is a [Google Cloud Function](https://cloud.google.com/functions/) который получает событие Sentry и публикует его в Salesforce.

## Requirements

* [Google Cloud SDK](https://cloud.google.com/sdk/)
* Доступ к учетной записи Sentry Outline.

## Build

```sh
yarn do sentry_webhook/build
```

## Deploy

Authenticate with `gcloud`:
  ```sh
  gcloud auth login
  ```
To deploy:
  ```sh
  yarn do sentry_webhook/deploy
  ```

## Configure Sentry Webhooks

* Log in to Outline's [Sentry account](https://sentry.io/outlinevpn/)
* Select a project (outline-client, outline-client-dev, outline-server, outline-server-dev).
* Обратите внимание, что этот процесс должен быть повторен для всех проектов Sentry.
* Включить плагин WebHooks на `https://sentry.io/settings/outlinevpn/<project>/plugins/`
* Установите конечную точку webhook на `https://sentry.io/settings/outlinevpn/<project>/plugins/webhooks/`
* Настройте оповещения для вызова веб-крючка на `https://sentry.io/settings/outlinevpn/<project>/alerts/`
* Создайте правила для запуска webhook на `https://sentry.io/settings/outlinevpn/<project>/alerts/rules/`
