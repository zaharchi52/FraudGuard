# Схема CSV-файлов

## Входные файлы: `data/history.csv` и `data/transactions.csv`

Заголовок (в точности и в указанном порядке в эталонном наборе):

```csv
transaction_id,client_id,timestamp,amount,currency,country,merchant_category,device_id
```

| Поле | Правило | Пример |
|---|---|---|
| `transaction_id` | Уникальная непустая строка | `H001` |
| `client_id` | Непустой синтетический идентификатор | `C001` |
| `timestamp` | ISO 8601 с часовым поясом | `2026-10-27T09:00:00Z` |
| `amount` | Конечное число строго больше нуля; точка для десятичных | `25.50` |
| `currency` | Трёхбуквенный код; MVP использует `EUR` | `EUR` |
| `country` | Непустой условный код страны | `DE` |
| `merchant_category` | Непустая категория | `groceries` |
| `device_id` | Непустой псевдоним устройства | `D001` |

## Выходной файл `reports/results.csv`

```csv
transaction_id,client_id,timestamp,amount,currency,risk_score,decision,risk_factors,profile_status,processing_status
```

## Выходной файл `reports/alerts.csv`

```csv
transaction_id,client_id,timestamp,amount,currency,risk_score,decision,risk_factors
```

Содержит только `REVIEW` и `BLOCK`.

## Выходной файл `reports/errors.csv`

```csv
source_file,line_number,transaction_id,error_code,message
```

`line_number` — номер строки физического CSV-файла, включая заголовок в нумерации. Сообщения ошибок не должны содержать чувствительных данных.
