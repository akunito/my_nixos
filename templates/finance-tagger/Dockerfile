FROM python:3.12-slim

RUN pip install --no-cache-dir flask gunicorn

WORKDIR /app
COPY app.py .
COPY templates/ templates/
COPY static/ static/

# Run as UID 1000 — rootless Docker maps this to host UID 100999
# (same as openclaw's node user = DB file owner)
USER 1000:1000

EXPOSE 8190

CMD ["gunicorn", "--bind", "0.0.0.0:8190", "--workers", "1", "--threads", "2", "--timeout", "30", "app:app"]
