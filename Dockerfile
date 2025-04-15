FROM python:3.9-slim
RUN apt-get update && apt-get install -y nginx && apt-get clean

COPY nginx.conf /etc/nginx/sites-available/default
RUN pip install flask
COPY app /app
WORKDIR /app
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80
CMD ["/entrypoint.sh"]
