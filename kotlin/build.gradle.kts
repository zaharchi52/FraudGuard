plugins {
    kotlin("jvm") version "2.1.20"
    application
}

group = "ru.fraudguard"
version = "1.0.0"

repositories {
    mavenCentral()
}

kotlin {
    jvmToolchain(17)
}

application {
    mainClass.set("fraudguard.MainKt")
}

dependencies {
<<<<<<< HEAD
    implementation("com.formdev:flatlaf:3.7.2")
=======
>>>>>>> 1d3001cacd41e209267ec19f5bcb4072cd6626dd
    testImplementation(kotlin("test-junit5"))
    testRuntimeOnly("org.junit.jupiter:junit-jupiter-engine:5.11.4")
}

tasks.test {
    useJUnitPlatform()
}
