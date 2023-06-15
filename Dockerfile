FROM adoptopenjdk:11-jdk-hotspot

# Set the working directory
WORKDIR /app

# Copy the JAR file to the container
COPY build/libs/project.jar /app/project.jar

# Install additional Java dependencies if needed
# Example: Install Maven
# RUN apt-get update && apt-get install -y maven

# Expose the port that the server will listen on
EXPOSE 9000

# Run the Java process
CMD ["java", "-jar", "project.jar"]
