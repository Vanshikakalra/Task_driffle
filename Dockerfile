FROM adoptopenjdk:11-jdk-hotspot
WORKDIR /app
# Copy the JAR file to the container
COPY build/libs/project.jar /app/project.jar
EXPOSE 9000
# Run the Java process
CMD ["java", "-jar", "project.jar"]
