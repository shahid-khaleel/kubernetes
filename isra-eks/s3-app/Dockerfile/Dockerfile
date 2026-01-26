FROM amazoncorretto:17
WORKDIR /app
COPY application.properties /app/
COPY s3-0.0.1-SNAPSHOT.jar /app/app.jar
ENTRYPOINT ["java","-jar","/app/app.jar","--spring.config.location=/app/application.properties"]

