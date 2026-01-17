pipeline {
    agent any

    environment {
        ANDROID_HOME = "C:\\Users\\SECULAB\\AppData\\Local\\Android\\Sdk"
        PATH = "${env.ANDROID_HOME}\\tools;${env.ANDROID_HOME}\\platform-tools;${env.PATH}"
        AVD_NAME = "Pixel_4_XL_2"
        GRADLE_USER_HOME = "${env.WORKSPACE}\\.gradle"
        APP_PACKAGE = "com.example.mobileapp"
        APK_OUTPUT_DIR = "C:\\ApksGenerated"
    }

    stages {
        // Checkout code from the Git repository
        stage('Checkout') {
            steps {
                echo 'Starting Checkout stage'
                git branch: 'main',
                    url: 'https://github.com/hnnayy/todo.git',
                    credentialsId: 'github-pat-global-test'  // Confirm credentials ID
                echo 'Checkout completed successfully'
            }
        }

        // Prepare folders for storing APKs
        stage('Prepare Destination Folders') {
            steps {
                echo 'Creating destination folder apk-outputs within the workspace if it does not exist.'
                bat 'if not exist apk-outputs mkdir apk-outputs'
                echo "Creating external folder ${env.APK_OUTPUT_DIR} if it does not exist."
                bat "if not exist \"${env.APK_OUTPUT_DIR}\" mkdir \"${env.APK_OUTPUT_DIR}\""
            }
        }

        // Clean the C:\ApksGenerated folder before storing new APK
        stage('Clean Folder C:\\ApksGenerated') {
            steps {
                echo "Cleaning ${env.APK_OUTPUT_DIR} folder before copying the new APK."
                bat "del /Q \"${env.APK_OUTPUT_DIR}\\*\""
            }
        }

        // Build the debug APK using Flutter
        stage('Build Application') {
            steps {
                echo 'Starting Build Application stage'
                bat 'git config --global --add safe.directory C:/flutter'
                bat 'flutter pub get'
                bat 'flutter build apk --debug'
                echo 'Build Application completed successfully'
            }
        }

        // SAST Mobile using MobSF
        stage('SAST Mobile') {
            steps {
                script {
                    echo 'Running Static Application Security Testing (SAST) using MobSF'
                    // Upload APK to MobSF
                    def uploadResponse = bat(script: 'curl -F "file=@build/app/outputs/flutter-apk/app-debug.apk" http://localhost:8000/api/v1/upload -H "Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac"', returnStdout: true).trim()
                    def uploadJson = readJSON text: uploadResponse
                    def apkHash = uploadJson.hash
                    echo "APK uploaded with hash: ${apkHash}"
                    env.APK_HASH = apkHash

                    // Scan the APK
                    def scanResponse = bat(script: "curl -X POST --url http://localhost:8000/api/v1/scan --data \"hash=${apkHash}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()
                    def scanJson = readJSON text: scanResponse
                    echo "Scan completed for hash: ${apkHash}"

                    // Get JSON report
                    def reportResponse = bat(script: "curl -X POST --url http://localhost:8000/api/v1/report_json --data \"hash=${apkHash}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()
                    def reportJson = readJSON text: reportResponse
                    echo "SAST Report generated"

                    // Check for high-risk vulnerabilities (example: if security_score < 50, fail)
                    if (reportJson.security_score < 50) {
                        error 'SAST found high-risk vulnerabilities. Pipeline failed.'
                    }

                    // Archive report
                    writeFile file: 'sast_report.json', text: reportResponse
                    archiveArtifacts artifacts: 'sast_report.json', allowEmptyArchive: false
                }
            }
        }

        // Verify if the debug APK was generated
        stage('Verify Generated APK') {
            steps {
                echo 'Verifying if the APK was generated in the expected folder:'
                bat 'dir build\\app\\outputs\\flutter-apk'
                bat '''
                    if exist build\\app\\outputs\\flutter-apk\\app-debug.apk (
                        echo APK generated successfully.
                    ) else (
                        echo APK NOT found in the build folder!
                        exit /b 1
                    )
                '''
            }
        }

        // Copy the generated APK to C:\ApksGenerated with a timestamp
        stage('Copy APK to C:\\ApksGenerated') {
            steps {
                script {
                    def timestamp = new Date().format("dd-MM-yyyy_HH-mm-ss")
                    echo "Copying APK to C:\\ApksGenerated with timestamp ${timestamp}"
                    bat """
                        copy "build\\app\\outputs\\flutter-apk\\app-debug.apk" "C:\\ApksGenerated\\todo-debug-${timestamp}.apk"
                    """
                    // Define the full path of the APK with timestamp for later use
                    env.APK_PATH = "C:\\ApksGenerated\\todo-debug-${timestamp}.apk"
                }
            }
        }

        // Start the Android emulator with a data wipe only if not already running
        stage('Start Emulator') {
            steps {
                script {
                    // Check if the emulator is running
                    def emulatorStatus = bat(script: "${env.ANDROID_HOME}\\platform-tools\\adb.exe devices", returnStdout: true)

                    if (!emulatorStatus.contains("emulator")) {
                        echo 'Emulator not running. Starting Android emulator with wiped data...'
                        bat """
                            start "Emulator" "${env.ANDROID_HOME}\\emulator\\emulator.exe" -avd "${env.AVD_NAME}" -no-window -no-audio -gpu swiftshader_indirect -wipe-data
                            timeout /t 30 /nobreak > nul
                            "${env.ANDROID_HOME}\\platform-tools\\adb.exe" wait-for-device
                        """
                        // Wait for a while to ensure the emulator initializes completely
                        sleep(time: 60, unit: 'SECONDS')
                        echo 'Emulator started and configured with wiped data'
                    } else {
                        echo 'Emulator is already running.'
                    }
                }
            }
        }

        // Wait for the emulator to finish booting
        stage('Wait for Emulator to Boot') {
            steps {
                script {
                    echo 'Waiting for emulator to fully boot'
                    def booted = false
                    def maxRetries = 30
                    def retries = 0
                    while (!booted && retries < maxRetries) {
                        try {
                            def output = bat(script: 'adb shell getprop init.svc.bootanim', returnStdout: true).trim()
                            if (output.contains("stopped")) {
                                booted = true
                                echo 'Emulator booted and is responsive.'
                            } else {
                                echo 'Emulator not fully responsive. Waiting...'
                                sleep time: 5, unit: 'SECONDS'
                                retries++
                            }
                        } catch (e) {
                            echo 'Error checking emulator. Retrying...'
                            sleep time: 5, unit: 'SECONDS'
                            retries++
                        }
                    }
                    if (!booted) {
                        error 'Emulator failed to boot within the expected time.'
                    }
                }
            }
        }

        // Install the generated APK on the emulator
        stage('Install APK on Emulator') {
            steps {
                echo "Installing APK on emulator from ${env.APK_PATH}"
                bat "adb install -r \"${env.APK_PATH}\""
            }
        }

        // DAST Mobile using MobSF
        stage('DAST Mobile') {
            steps {
                script {
                    echo 'Running Dynamic Application Security Testing (DAST) using MobSF'
                    // Assume apkHash is available from SAST stage (store in env or file)
                    // For simplicity, re-upload or use stored hash. Here, assume we have apkHash from previous stage.
                    // In practice, pass apkHash via environment variable or file.

                    // Start Dynamic Analysis
                    def startResponse = bat(script: "curl -X POST --url http://localhost:8000/api/v1/dynamic/start_analysis --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()
                    def startJson = readJSON text: startResponse
                    echo "Dynamic analysis started"

                    // Optionally, run some tests or wait
                    sleep(time: 30, unit: 'SECONDS')  // Simulate running app and tests

                    // Stop Dynamic Analysis
                    bat(script: "curl -X POST --url http://localhost:8000/api/v1/dynamic/stop_analysis --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()
                    echo "Dynamic analysis stopped"

                    // Get Dynamic Report
                    def dastReportResponse = bat(script: "curl -X POST --url http://localhost:8000/api/v1/dynamic/report_json --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()
                    def dastReportJson = readJSON text: dastReportResponse
                    echo "DAST Report generated"

                    // Check for issues (example: if trackers detected > 0, warn or fail)
                    if (dastReportJson.trackers?.detected_trackers > 0) {
                        echo 'Warning: Trackers detected in DAST'
                        // Optional: error 'DAST found trackers. Pipeline failed.'
                    }

                    // Archive report
                    writeFile file: 'dast_report.json', text: dastReportResponse
                    archiveArtifacts artifacts: 'dast_report.json', allowEmptyArchive: false
                }
            }
        }

        // Verify if the APK is installed on the emulator
        stage('Verify Installed APK') {
            steps {
                echo 'Checking if APK is installed on emulator'
                bat """
                    adb shell pm list packages | findstr "${env.APP_PACKAGE}"
                """
            }
        }

        stage('Prepare Environment') {
            steps {
                echo 'Disabling animations on the emulator'
                // Disable animations on the emulator to avoid interference in tests
                bat 'adb shell settings put global window_animation_scale 0'
                bat 'adb shell settings put global transition_animation_scale 0'
                bat 'adb shell settings put global animator_duration_scale 0'
            }
        }

        // Run automated tests on the installed APK (assuming Flutter integration tests or similar)
        stage('Run Tests') {
            steps {
                echo 'Running Automated Tests'
                // For Flutter, you might need to run flutter drive or similar; adjust as needed
                bat 'flutter test integration_test'  // Example; confirm if you have integration tests
                echo 'Tests completed successfully'
            }
        }

        // Publish the test report as an HTML file (adjust path if needed)
        stage('Publish Test Report (HTML)') {
            steps {
                echo 'Publishing HTML Test Report'
                publishHTML(target: [
                    allowMissing: false,
                    alwaysLinkToLastBuild: true,
                    keepAll: true,
                    reportDir: 'build/reports/tests/testDebugUnitTest',  // Adjust for Flutter test reports
                    reportFiles: 'index.html',
                    reportName: 'Flutter Test Report'
                ])
                echo 'HTML Test Report published'
            }
        }

        // Build the release APK for deployment
        stage('Build APK Release') {
            when {
                expression { currentBuild.result == null || currentBuild.result == 'SUCCESS' }
            }
            steps {
                echo 'Starting Build APK Release'
                bat 'flutter build apk --release'
                echo 'Build APK Release completed'
            }
        }

        // Verify if the release APK was generated
        stage('Verify Generated APK Release') {
            steps {
                echo 'Verifying release APK'
                bat 'dir build\\app\\outputs\\flutter-apk'
            }
        }

        // Clean old APKs from apk-outputs before copying new APK
        stage('Clean APK Outputs') {
            steps {
                echo 'Cleaning old APK files from apk-outputs folder'
                bat 'del /Q apk-outputs\\*'
            }
        }

        // Copy the APK to a workspace folder for archiving with a timestamp
        stage('Copy APK to apk-outputs') {
            steps {
                script {
                    def timestamp = new Date().format("dd-MM-yyyy_HH-mm-ss")
                    echo "Copying APK to the apk-outputs folder within the workspace with timestamp ${timestamp}"
                    bat """
                        copy "build\\app\\outputs\\flutter-apk\\app-debug.apk" "apk-outputs\\todo-debug-${timestamp}.apk"
                    """
                    // Sets the full APK path with timestamp for later use
                    env.APK_PATH_WORKSPACE = "apk-outputs\\todo-debug-${timestamp}.apk"
                }
            }
        }

        // Verify if the APK is in the apk-outputs folder
        stage('Verify APK in New Folder (apk-outputs)') {
            steps {
                echo 'Verifying if the APK was copied to the apk-outputs folder'
                bat 'dir apk-outputs'
                bat '''
                    set apkFound=false
                    for %%f in (apk-outputs\\todo-debug-*.apk) do (
                        set apkFound=true
                        echo APK found: %%f
                        goto :EOF
                    )
                    if not %apkFound% (
                        echo APK NOT found in the apk-outputs folder!
                        exit /b 1
                    )
                '''
            }
        }

        // Stop the Android emulator after testing
        stage('Stop Emulator') {
            steps {
                echo 'Stopping Emulator'
                bat 'adb emu kill'
                echo 'Emulator stopped'
            }
        }
    }

    post {
        success {
            // Uses a wildcard to find any APK that starts with "todo-debug"
            archiveArtifacts artifacts: 'apk-outputs/todo-debug-*.apk', allowEmptyArchive: false
            archiveArtifacts artifacts: 'build/app/outputs/flutter-apk/app-release.apk', allowEmptyArchive: false
        }
        failure {
            echo 'Build failed. No APK generated due to test failures.'
        }
        always {
            echo 'Pipeline completed'
        }
    }
}