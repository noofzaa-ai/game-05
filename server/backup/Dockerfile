FROM postgres:17-alpine@sha256:b0f9560a2de083e2cc7382e75f808c7381a32852a7ec49117deedb300e552b24
RUN apk add --no-cache python3 py3-boto3
WORKDIR /opt/zorx
COPY backup.py /opt/zorx/backup.py
USER 10001:10001
ENTRYPOINT ["python3", "/opt/zorx/backup.py"]
CMD ["backup"]
