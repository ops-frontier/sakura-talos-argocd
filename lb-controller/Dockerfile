FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY controller.py .
# セキュリティ: 非 root ユーザで実行
USER nobody
ENTRYPOINT ["python", "-u", "controller.py"]
