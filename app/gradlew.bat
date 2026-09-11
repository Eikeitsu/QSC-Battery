@ECHO OFF
SETLOCAL
SET DIR=%~dp0
SET WRAPPER_JAR=%DIR%gradle\wrapper\gradle-wrapper.jar
IF NOT EXIST "%WRAPPER_JAR%" (
  ECHO gradle-wrapper.jar missing. Run: gradle wrapper --gradle-version 9.3.1
  EXIT /B 1
)
java -classpath "%WRAPPER_JAR%" org.gradle.wrapper.GradleWrapperMain %*
