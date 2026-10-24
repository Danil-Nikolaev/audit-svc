# Итоговая работа: развёртывание и мониторинг audit-svc

Репозиторий: <https://github.com/Danil-Nikolaev/audit-svc>

Платформа: GitHub Actions, GitHub Container Registry и self-hosted ARM64 runner на Ubuntu 24.04.

## 1. Сборка и публикация образа

Образ собирается многоступенчатым `Dockerfile`. Финальный процесс работает от пользователя `audit-svc` с UID/GID 10001. В образ установлены команды `server`, `migrate` и `generate`.

Локальная проверка образа:

```text
uid=10001(audit-svc) gid=10001(audit-svc) groups=10001(audit-svc),100(users)
/usr/local/bin/server
/usr/local/bin/migrate
/usr/local/bin/generate
```

Тесты исходного сервиса:

```text
collected 6 items
tests/test_main.py ......                                              [100%]
============================== 6 passed ===============================
```

### Пайплайн main

Скриншот графа пайплайна и публикации образа будет добавлен после первого запуска.

### Пайплайн защищённого тега

Скриншот графа релизного пайплайна и полный лог deploy-задачи будут добавлены после релиза `v1.0.0`.

## 2. PostgreSQL и секреты

PostgreSQL 17 работает в контейнере без опубликованного порта. Данные находятся в именованном томе `audit-postgres-data`. Пользователь `audit_svc` и принадлежащая ему БД `audit` создаются модулями `community.postgresql`.

Пароли находятся только в зашифрованном `deploy/inventories/prod/group_vars/all/vault.yml`. Пароль расшифровки хранится в защищённом GitHub Environment secret и передаётся Ansible через `deploy/vault-pass.sh`.

## 3. Развёртывание и перечитывание конфигурации

Релизный job запускается только для тегов `vX.Y.Z` на self-hosted runner с меткой `deploy`. Конфигурация создаётся Ansible-модулем `template` с правами `root:audit-svc 0640`; в контейнер монтируется каталог конфигурации.

При изменении файла handler выполняет внутренний `POST /reload`. Контейнер приложения не перезапускается.

### Идемпотентность

Локальный проверочный запуск перед публикацией:

```text
PLAY RECAP *********************************************************************
localhost : ok=17 changed=14 unreachable=0 failed=0 skipped=0 rescued=0 ignored=0
```

Повторный запуск без изменений:

```text
PLAY RECAP *********************************************************************
localhost : ok=15 changed=0 unreachable=0 failed=0 skipped=0 rescued=0 ignored=0
```

После релиза сюда также будет добавлена ссылка на полный CI-лог.

### Смена пароля

Будут зафиксированы:

1. `StartedAt` до смены пароля;
2. задачи обновления пользователя, шаблона и reload handler со статусом `changed`;
3. неизменившийся `StartedAt`;
4. сообщение `config reloaded, reconnected to the database`;
5. увеличение `audit_config_reloads_total{result="success"}` и ответ `/healthz` 200.

## 4. Nginx и nginx-exporter

Проверки после первого релиза:

```bash
curl -s localhost:8088/healthz
curl -s -o /dev/null -w '%{http_code}\n' -X POST localhost:8088/reload
curl -s -o /dev/null -w '%{http_code}\n' -X POST 'localhost:8088/reload?x=1'
curl -s -o /dev/null -w '%{http_code}\n' -X POST localhost:8088//reload
curl -s -o /dev/null -w '%{http_code}\n' -X POST localhost:8088/%72eload
docker logs audit-svc 2>&1 | grep -c 'config reload'
docker ps --format '{{.Names}}\t{{.Ports}}'
curl -s localhost:9113/metrics | grep '^nginx_up '
```

Фактический результат:

```text
reload_log_count_before=1
healthz=200
reload=404
reload_query=404
double_slash=404
encoded_r=404
reload_log_count_after=1
stub_status_main=404
nginx_up 1

audit-nginx-exporter  0.0.0.0:9113->9113/tcp
audit-nginx           80/tcp, 0.0.0.0:8088->8080/tcp
audit-svc             8080/tcp
audit-postgres        5432/tcp
```

У `audit-svc` и PostgreSQL в колонке `Ports` видны только внутренние exposed-порты, без привязки к адресу хоста.

## 5. Prometheus и Grafana

Prometheus собирает метрики сервиса через Nginx и метрики Nginx через exporter. Собственный dashboard содержит панели событий в секунду по приложениям, процентов HTTP-кодов и состояния `UP`/`DOWN`. Второй dashboard импортирован из официального репозитория nginx-prometheus-exporter.

Проверка API Prometheus:

```text
audit-svc  up
nginx      up
```

После запуска будут добавлены скриншоты:

- обе цели Prometheus в состоянии `UP`;
- dashboard audit-svc после десятиминутной нагрузки;
- официальный dashboard Nginx;
- панель сервиса в состояниях `UP` и `DOWN`.
