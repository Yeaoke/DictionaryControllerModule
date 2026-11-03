# DictionaryControllerModule

Java-библиотека для загрузки справочников НСИ Минздрава в PostgreSQL. Встраивается в Spring Boot-приложение: принимает OID и ID пользователя, сравнивает версию НСИ с последней загруженной версией, получает данные и передаёт их процедуре соответствующего справочника.


## Что входит в модуль

- Клиент НСИ на WebClient / Reactor Netty с TLS через BoringSSL и PKCS12 truststore.
- Каталог из 64 определений: OID → таблицы, процедура, ключи, сопоставление полей.
- Универсальный преобразователь значений и пакетная запись через JDBC.
- Проверки паспорта, полноты выгрузки, повторяющихся ключей и изменения версии во время скачивания.
- PostgreSQL-процедуры для применения данных и ведения истории загрузок.
- Миграции Flyway и модульные/интеграционные тесты.

Источник HTTP-выгрузки в текущей реализации — Минздрав.

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

Файл truststore читается как путь файловой системы, а не `classpath:`-ресурс. `.env` сам по себе не загружается библиотекой: переменные должны быть переданы процессу IDE, оболочкой или средствами развёртывания. Ключи и пароли не следует включать в Git.

Принимающее приложение может предоставить собственный bean `WebClient` с именем `minzdravWebClient`; тогда штатный TLS-клиент библиотеки не создаётся.

## Вызов загрузки

Получите `DictionaryImportService` через внедрение зависимостей и вызовите:
