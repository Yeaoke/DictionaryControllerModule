# DictionaryControllerModule

Java-библиотека для загрузки справочников НСИ Минздрава. Встраивается в Spring Boot-приложение: принимает OID и ID пользователя, сравнивает версию НСИ с последней загруженной версией, получает данные и передаёт их процедуре соответствующего справочника.

## Что входит в модуль

- Клиент НСИ на WebClient / Reactor Netty с TLS через BoringSSL и PKCS12 truststore.
- Каталог из 64 определений: OID → таблицы, процедура, ключи, сопоставление полей.
- Универсальный преобразователь значений и пакетная запись через JDBC.
- Проверки паспорта, полноты выгрузки, повторяющихся ключей и изменения версии во время скачивания.
- PostgreSQL-процедуры для применения данных и ведения истории загрузок.
- Миграции Flyway и модульные/интеграционные тесты.

Источник HTTP-выгрузки справочников — Минздрав.

## Требования

- Java 21; сборка через Maven Wrapper.
- Проект собран на Spring Boot 4.1.2; совместимость с другой основной версией Spring Boot отдельно не гарантируется.
- PostgreSQL с подготовленными схемами, таблицами и процедурами.
- Ключ API НСИ и доступ к `https://nsi.rosminzdrav.ru/port`.
- PKCS12 truststore с доверенными сертификатами для НСИ; штатная конфигурация требует доступного нативного TLS-провайдера.

## Подключение

В репозитории библиотеки:

```powershell
.\mvnw.cmd clean install
```

В POM принимающего приложения добавьте зависимость. Написание `conrollerversion` соответствует текущему artifactId:

```xml
<dependency>
    <groupId>com.example.app</groupId>
    <artifactId>conrollerversion</artifactId>
    <version>0.0.1-SNAPSHOT</version>
</dependency>
```

Для подключения на другой машине артефакт нужно опубликовать в доступном Maven-репозитории. `install` помещает его только в локальный репозиторий текущего пользователя.

Импортируйте конфигурацию в Spring Boot-приложение:

```java
import com.example.app.config.DictionaryLoaderConfiguration;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;

@Configuration(proxyBeanMethods = false)
@Import(DictionaryLoaderConfiguration.class)
public class DictionariesConfiguration {
}
```

Принимающее приложение предоставляет `DataSource`, JDBC-менеджер транзакций и `WebClient.Builder` через Spring Boot auto-configuration. Глобальное сканирование всех пакетов библиотеки не требуется.

Пример конфигурации приложения:

```yaml
spring:
  config:
    import: classpath:nsi-dictionaries.yaml
  datasource:
    url: ${POSTGRES_URL}
    username: ${POSTGRES_USERNAME}
    password: ${POSTGRES_PASSWORD}
  flyway:
    enabled: false # БД подготовлена отдельно; вариант применения миграций ниже.

nsi:
  minzdrav:
    base-url: https://nsi.rosminzdrav.ru/port
    user-key: ${NSI_USER_KEY}
    trust-store: ${NSI_TRUST_STORE}
    trust-store-password: ${NSI_TRUST_STORE_PASSWORD}

dictionary:
  loading:
    page-size: 500
    jdbc-batch-size: 500
    max-concurrent-imports: 2
```

Файл truststore читается как путь файловой системы, а не `classpath:`-ресурс. `.env` сам по себе не загружается библиотекой: переменные должны быть переданы процессу IDE, оболочкой или средствами развёртывания.

Принимающее приложение может предоставить собственный bean `WebClient` с именем `minzdravWebClient`; тогда штатный TLS-клиент библиотеки не создаётся.

## Вызов загрузки

Получите `DictionaryImportService` через внедрение зависимостей и вызовите:

```java
var result = importService.load("1.2.643.5.1.13.13.11.1009", userId);

if (result.isEmpty()) {
    // Эта версия уже загружена.
} else {
    var batch = result.get();
    // Обработайте batch.status(): success, partial или error.
    // Статистика загрузки доступна в полях результата.
}
```

`userId` — ID существующего пользователя из `access_work.users_v`, а не ключ API НСИ. Метод синхронный; вызывать его следует вне активной Spring-транзакции.

## База данных и миграции

Миграции применяются последовательно:

| Версия | Назначение |
|---|---|
| V1 | Создание служебных таблиц загрузки |
| V2 | Создание целевых таблиц справочников |
| V3 | Подготовка метаданных загрузки direction_type |
| V4 | Создание процедуры загрузки direction_type |
| V5 | Создание промежуточных raw-таблиц |
| V6 | Обновление контракта результата загрузки direction_type |
| V7 | Создание процедуры загрузки patient_sex |
| V8 | Восстановление процедур загрузки |
| V9 | Добавление процедур остальных справочников |
| V10 | Установка ограничений строковых полей |
| V11 | Уточнение ограничений по результатам измерения данных НСИ |

Для каждого справочника предусмотрены две таблицы. Java-загрузчик записывает полученный снимок в `data.dsa_raw_<entity>`, затем процедура `dsa_data_load.load_<entity>` применяет его к `data.<entity>`. Например:

| Справочник | Raw-таблица | Целевая таблица |
|---|---|---|
| Виды медицинских направлений | `data.dsa_raw_direction_type` | `data.direction_type` |
| Пол пациента | `data.dsa_raw_patient_sex` | `data.patient_sex` |
| Методы высокотехнологичного лечения | `data.dsa_raw_high_tech_treatment_method` | `data.high_tech_treatment_method` |

OID, имена таблиц, процедура и сопоставление полей задаются в `src/main/resources/nsi-dictionaries.yaml`. Перед новым применением raw-таблица очищается внутри транзакции. При полном успехе процедура фиксирует новую версию; результат партии сохраняется в `data.dsa_load_batch`.

Обычно используется одна БД `dsa`:

| Объект | Назначение |
|---|---|
| `data.dsa_raw_<entity>` | Промежуточные строки очередной загрузки |
| `data.<entity>` | Принятые данные справочника |
| `data.dsa_loaded_version` | Последняя успешно загруженная версия по entity |
| `data.dsa_load_batch` | Результаты партий и статистика |
| `dsa_data_load.load_<entity>` | Процедура применения конкретного справочника |
| `access_work.users_v` | Внешнее представление/отношение пользователей |
| `data.log_level`, `data.system_log` | Внешние объекты журналирования |

Внешние зависимости предоставляет принимающая система. Процедуры ожидают `access_work.users_v(id, full_name)`, `data.log_level(id, sys_name)` и `data.system_log(log_date, log_level_id, record_details)`. В `log_level.sys_name` требуются уровни `info` и `warning`: это уровни журнала, не названия источников `minzdrav`/`foms`. Для переданного ID должна находиться ровно одна запись пользователя с `full_name`, отличным от NULL.

Контракт вызова процедуры:

```sql
CALL dsa_data_load.load_direction_type(
    7::bigint, 'version'::varchar, 'source-url'::varchar, NULL::bigint
);
```

Последний параметр — `INOUT p_batch_id bigint`. Этот пример показывает контракт; обычный импорт следует запускать через сервис, который предварительно подготавливает raw-данные.

В текущей ветке находятся миграции **V1–V11**. Итоговые ограничения строк задаёт `V11__nsi_measured_name_limits.sql`: лимиты `name` различаются по справочникам, остальные перечисленные строки ограничены 5000 символами. Например, `high_tech_treatment_method.name` допускает 1500 символов. Служебные ограничения не становятся автоматически равными 5000.

SQL лежит в `deployment/migrations`, вне стандартных ресурсов JAR. При развёртывании эти файлы нужно доставить отдельно. Пример для отдельного миграционного запуска либо приложения, которому поручены миграции:

```yaml
spring:
  flyway:
    enabled: true
    locations: filesystem:deployment/migrations
    default-schema: data
    schemas: data,dsa_data_load
    baseline-on-migrate: false
```

Относительный путь разрешается от рабочей директории процесса. Если основная система уже использует Flyway, нужно согласовать расположение миграций, их версии и таблицу истории; нельзя без проверки смешивать два набора V1…V11.

Применённые миграции не переименовывают и не редактируют. При несовпадении checksum восстановите исходный файл; дальнейшие изменения оформляйте новой версией. Если в существующей базе уже применялась другая V11, текущая V11 не является её автоматической заменой. Удаление истории не отменяет SQL-изменения.

`deployment/reference-sql` содержит справочные DDL и не заменяет последовательность миграций. При расхождении размеров строк ориентируйтесь на итог миграций и согласованный YAML.

