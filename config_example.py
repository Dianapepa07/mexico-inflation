"""
config_example.py
-----------------
1) Copy this file and rename the copy to  config.py
2) Type your MySQL password in 'password'
config.py is listed in .gitignore: your password is NEVER uploaded to GitHub.
"""
MYSQL_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "YOUR_PASSWORD_HERE",
    "database": "mexico_inflation",
    "charset": "utf8mb4",
}

MONGO_URI = "mongodb://localhost:27017/"
MONGO_DB_NAME = "mexico_inflation"

CSV_PATH = "../data/INP_INP20261125012813.CSV"
