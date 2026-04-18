FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . ./monitor_hub/
EXPOSE 5000
CMD ["python", "-m", "monitor_hub"]
