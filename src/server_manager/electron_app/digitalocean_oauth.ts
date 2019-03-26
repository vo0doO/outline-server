// Copyright 2018 The Outline Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import * as bodyParser from 'body-parser';
import * as crypto from 'crypto';
import * as electron from 'electron';
import * as express from 'express';
import * as http from 'http';
import * as path from 'path';
import * as request from 'request';

const REGISTERED_REDIRECTS: Array<{clientId: string, port: number}> = [
  {clientId: '23b579be1d5e8ad7a44e1a4fab5e7f23118ad7559923e63af7008eb428c039eb', port: 55189},
  {clientId: '4af51205e8d0d8f4a5b84a6b5ca9ea7124f914a5621b6a731ce433c2c7db533b', port: 60434},
  {clientId: '706928a1c91cbd646c4e0d744c8cbdfbf555a944b821ac7812a7314a4649683a', port: 61437}
];

function randomValueHex(len: number): string {
  return crypto.randomBytes(Math.ceil(len / 2))
      .toString('hex')  // convert to hexadecimal format
      .slice(0, len);   // return required number of characters
}

interface ServerError extends Error {
  code: string;
}

// Заставляет сервер прослушивать каждый из перечисленных портов, пока не будет открыт один.
// Возвращает индекс используемого порта.
function listenOnFirstPort(server: http.Server, portList: number[]): Promise<number> {
  let portIdx = 0;
  return new Promise((resolve, reject) => {
    server.once('listening', () => {
      console.log(`Listening on port ${portList[portIdx]}`);
      resolve(portIdx);
    });
    server.on('error', (error: ServerError) => {
      if (error.code === 'EADDRINUSE') {
        console.log(`Port ${portList[portIdx]} already in use`);
        portIdx += 1;
        if (portIdx < portList.length) {
          const port = portList[portIdx];
          console.log(`Trying port ${port}`);
          server.listen({host: 'localhost', port, exclusive: true});
          return;
        }
      }
      server.close();
      reject(error);
    });
    server.listen({host: 'localhost', port: portList[portIdx], exclusive: true});
  });
}

// Увидеть https://developers.digitalocean.com/documentation/v2/#get-user-information
interface Account {
  droplet_limit: number;
  floating_ip_limit: number;
  email: string;
  uuid: string;
  email_verified: boolean;
  status: string;
  status_message: string;
}

// Запрашивает API DigitalOcean для получения информации об учетной записи пользователя..
function getAccount(accessToken: string): Promise<Account> {
  return new Promise((resolve, reject) => {
    request(
        {
          url: 'https://api.digitalocean.com/v2/account',
          headers: {
            'User-Agent': 'Outline Manager',
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${accessToken}`
          }
        },
        (error, response, body) => {
          if (error) {
            return reject(error);
          }
          const bodyJson: {account: Account} = JSON.parse(body);
          return resolve(bodyJson.account as Account);
        });
  });
}

function closeWindowHtml(messageHtml: string) {
  return `<html><script>window.close()</script><body>${messageHtml}. You can close this window.</body></html>`;
}

// Запускает oauth-поток DigitalOcean и возвращает токен доступа..
// Увидеть https://developers.digitalocean.com/documentation/oauth/ для OAuth API.
export function runOauth(): OauthSession {
  const secret = randomValueHex(16);

  const app = express();
  const server = http.createServer(app);
  server.on('close', () => console.log('Oauth server closed'));

  let isCancelled = false;
  // Disable caching.
  app.use((req, res, next) => {
    res.header('Cache-Control', 'no-cache, no-store, must-revalidate');
    next();
  });
  // Check for cancellation.
  app.use((req, res, next) => {
    if (isCancelled) {
      res.status(503).send(closeWindowHtml('Authentication cancelled'));
    } else {
      next();
    }
  });

  // Это обратный вызов для обратного вызова DigitalOcean. Он обслуживает JavaScript, который будет
  // Извлеките токен доступа из хеша и отправьте его обратно на наш http-сервер..
  app.get('/', (request, response) => {
    response.send(`<html>
          <head><title>Authenticating...</title></head>
          <body>
              <noscript>You need to enable JavaScript in order for the DigitalOcean authentication to work.</noscript>
              <form id="form" method="POST">
                  <input id="params" type="hidden" name="params"></input>
              </form>
              <script>
                  var paramsStr = location.hash.substr(1);
                  var form = document.getElementById("form");
                  document.getElementById("params").setAttribute("value", paramsStr);
                  form.submit();
              </script>
          </body>
      </html>`);
  });

  const rejectWrapper = {reject: (error: Error) => {}};
  const result = new Promise<string>((resolve, reject) => {
    rejectWrapper.reject = reject;
    // Это конечная точка POST, которая получает токен доступа и перенаправляет в DigitalOcean
    // для пользователя, чтобы завершить создание своей учетной записи, или на страницу, которая закрывает окно.
    app.post('/', bodyParser.urlencoded({type: '*/*', extended: false}), (request, response) => {
      server.close();

      const params = new URLSearchParams(request.body.params);
      if (params.get('error')) {
        response.status(400).send(closeWindowHtml('Ошибка аутентификации'));
        reject(new Error(`DigitalOcean OAuth error: ${params.get('error_description')}`));
        return;
      }
      const requestSecret = params.get('state');
      if (requestSecret !== secret) {
        response.status(400).send(closeWindowHtml('Ошибка аутентификации'));
        reject(new Error(`Expected secret ${secret}. Got ${requestSecret}`));
        return;
      }
      const accessToken = params.get('access_token');
      if (accessToken) {
        getAccount(accessToken)
            .then((account) => {
              if (account.status === 'active') {
                response.send(closeWindowHtml('Аутентификация прошла успешно'));
              } else {
                response.redirect('https://cloud.digitalocean.com');
              }
              resolve(accessToken);
            })
            .catch(reject);
      } else {
        response.status(400).send(closeWindowHtml('Authentication failed'));
        reject(new Error('No access_token on OAuth response'));
      }
    });

    // К сожалению, DigitalOcean сопоставляет порт в URL перенаправления с зарегистрированными.
    // Мы зарегистрировали приложение 3 раза с разными портами, поэтому у нас есть запасные варианты на случай
    // первый порт используется.
    listenOnFirstPort(server, REGISTERED_REDIRECTS.map(e => e.port))
        .then((index) => {
          const {port, clientId} = REGISTERED_REDIRECTS[index];
          const address = server.address();
          console.log(`OAuth target listening on ${address.address}:${address.port}`);

          const oauthUrl = `https://cloud.digitalocean.com/v1/oauth/authorize?client_id=${
              encodeURIComponent(
                  clientId)}&response_type=token&scope=read%20write&redirect_uri=http://localhost:${
              encodeURIComponent(port.toString())}/&state=${encodeURIComponent(secret)}`;
          console.log(`Opening OAuth URL ${oauthUrl}`);
          electron.shell.openExternal(oauthUrl);
        })
        .catch((error) => {
          if (error.code && error.code === 'EADDRINUSE') {
            return reject(new Error('All OAuth ports are in use'));
          }
          reject(error);
        });
  });
  return {
    result,
    isCancelled() {
      return isCancelled;
    },
    cancel() {
      console.log('Session cancelled');
      isCancelled = true;
      server.close();
      rejectWrapper.reject(new Error('Authentication cancelled'));
    }
  };
}
