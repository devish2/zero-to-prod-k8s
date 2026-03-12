FROM alpine:3.20
RUN apk add --no-cache postgresql16-client
RUN adduser -D -u 10001 jobuser
COPY alert.sh /alert.sh
RUN chmod +x /alert.sh
USER 10001
CMD ["/alert.sh"]