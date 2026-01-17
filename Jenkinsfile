import groovy.json.JsonSlurperClassic 

// --- HELPER METHODS ---

@NonCPS
def extractHashFromResponse(String response) {
    // Cari text di dalam tanda kutip setelah "hash":
    def matcher = response =~ /"hash"\s*:\s*"([^"]+)"/
    if (matcher.find()) {
        return matcher.group(1)
    }
    return ""
}

@NonCPS
def cleanJsonString(String rawOutput) {
    // Cari kurung kurawal pembuka '{' pertama dan penutup '}' terakhir
    // Ini berguna untuk membuang log command Windows (seperti C:\Path> curl...)
    int firstBrace = rawOutput.indexOf('{')
    int lastBrace = rawOutput.lastIndexOf('}')

    if (firstBrace == -1 || lastBrace == -1) {
        return null
    }
    // Mengambil hanya bagian JSON yang valid
    return rawOutput.substring(firstBrace, lastBrace + 1)
}

// -----------------------------------------------------------------------

pipeline {
    agent any

    environment {
        ANDROID_HOME = "C:\\Users\\SECULAB\\AppData\\Local\\Android\\Sdk"
        PATH = "${env.ANDROID_HOME}\\tools;${env.ANDROID_HOME}\\platform-tools;${env.PATH}"
        AVD_NAME = "Pixel_4_XL_2"
        APP_PACKAGE = "com.example.mobileapp"
        APK_OUTPUT_DIR = "C:\\ApksGenerated"
    }

    stages {
        stage('Checkout') {
            steps {
                echo 'Starting Checkout stage'
                git branch: 'main',
                    url: 'https://github.com/hnnayy/todo.git',
                    credentialsId: 'github-pat-global-test'
            }
        }

        stage('Prepare Folders') {
            steps {
                bat 'if not exist apk-outputs mkdir apk-outputs'
                bat "if not exist \"${env.APK_OUTPUT_DIR}\" mkdir \"${env.APK_OUTPUT_DIR}\""
            }
        }

        // Stage Request: Clean External Folder
        stage('Clean Folder C:\\ApksGenerated') {
            steps {
                echo "Cleaning ${env.APK_OUTPUT_DIR} folder before copying the new APK."
                bat "del /Q \"${env.APK_OUTPUT_DIR}\\*\""
            }
        }

        stage('Build Application') {
            steps {
                echo 'Starting Build Application stage'
                bat 'git config --global --add safe.directory C:/flutter'
                bat 'flutter pub get'
                bat 'flutter build apk --debug'
            }
        }

        // --- SAST STAGE ---
        stage('SAST Mobile') {
            steps {
                script {
                    echo 'Running SAST...'
                    
                    // 1. Upload
                    // Menggunakan @curl untuk meminimalkan output log command
                    def uploadResponse = bat(script: '@curl -s -F "file=@build/app/outputs/flutter-apk/app-debug.apk" http://localhost:8000/api/v1/upload -H "Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac"', returnStdout: true).trim()
                    String apkHash = extractHashFromResponse(uploadResponse)
                    
                    if (apkHash == "") { error "Upload failed. Raw response: " + uploadResponse }
                    env.APK_HASH = apkHash
                    echo "SAST Hash: ${apkHash}"

                    // 2. Scan
                    bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/scan --data \"hash=${apkHash}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()

                    // 3. Get JSON Report
                    def rawOutput = bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/report_json --data \"hash=${apkHash}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()

                    // 4. Clean & Save JSON Only
                    String jsonString = cleanJsonString(rawOutput)
                    
                    if (jsonString != null) {
                        writeFile file: 'sast_report.json', text: jsonString
                        echo "SAST JSON Report saved successfully."
                    } else {
                        echo "WARNING: Failed to extract JSON from SAST output."
                    }
                    
                    // Archive only the JSON report
                    archiveArtifacts artifacts: 'sast_report.json', allowEmptyArchive: true
                }
            }
        }

        stage('Setup Emulator') {
            steps {
                script {
                    def devices = bat(script: "adb devices", returnStdout: true)
                    if (!devices.contains("emulator")) {
                        bat "start /b \"\" \"${env.ANDROID_HOME}\\emulator\\emulator.exe\" -avd \"${env.AVD_NAME}\" -no-window -no-audio -gpu swiftshader_indirect -wipe-data"
                        sleep(time: 60, unit: 'SECONDS')
                        bat "adb wait-for-device"
                    }
                    sleep(time: 15, unit: 'SECONDS')
                }
            }
        }

        stage('Install APK') {
            steps {
                script {
                    def timestamp = new Date().format("dd-MM-yyyy_HH-mm-ss")
                    bat "copy \"build\\app\\outputs\\flutter-apk\\app-debug.apk\" \"apk-outputs\\todo-debug-${timestamp}.apk\""
                    env.APK_PATH = "apk-outputs\\todo-debug-${timestamp}.apk"
                    bat(script: "adb uninstall ${env.APP_PACKAGE}", returnStatus: true) 
                    bat "adb install -r \"${env.APK_PATH}\""
                }
            }
        }

        // --- DAST STAGE (WITH INTERACTION) ---
        stage('DAST Mobile') {
            steps {
                script {
                    echo 'Running DAST (Interactive)...'
                    
                    // 1. START Analysis
                    bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/dynamic/start_analysis --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()
                    
                    // FLUTTER WARM UP (Tunggu UI Loading)
                    echo "Waiting 20s for App/Flutter Engine to hydrate..."
                    sleep(time: 20, unit: 'SECONDS') 

                    // 2. INTERACTION PHASE (Hybrid: Keyboard + Monkey)
                    echo "Starting Automated Interaction..."

                    // A. Logical Input (Tab & Enter untuk Form)
                    try {
                        bat "adb shell input keyevent 61" // Tab
                        bat "adb shell input keyevent 61" // Tab
                        bat "adb shell input text \"TEST_DAST\"" // Ketik text
                        bat "adb shell input keyevent 66" // Enter
                        bat "adb shell input keyevent 61" // Tab
                        bat "adb shell input keyevent 66" // Enter
                    } catch (Exception e) {
                        echo "Input simulation warning: ${e.getMessage()}"
                    }

                    // B. Aggressive Monkey (Klik Acak Terarah)
                    echo "Running Monkey..."
                    try {
                        // pct-syskeys 0 (No volume/back), pct-nav 20 (D-pad), throttle 100ms
                        bat "adb shell monkey -p ${env.APP_PACKAGE} --pct-syskeys 0 --pct-nav 20 --pct-majornav 20 --pct-touch 40 --pct-motion 20 --throttle 100 -v 2000"
                    } catch (Exception e) {
                        echo "Monkey finished."
                    }

                    // Tunggu sebentar untuk capture log pasca interaksi
                    sleep(time: 15, unit: 'SECONDS') 

                    // 3. STOP Analysis
                    bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/dynamic/stop_analysis --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()

                    // 4. Get JSON Report
                    def rawOutput = bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/dynamic/report_json --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()

                    // 5. Clean & Save JSON Only
                    String jsonString = cleanJsonString(rawOutput)
                    
                    if (jsonString != null) {
                        writeFile file: 'dast_report.json', text: jsonString
                        echo "DAST JSON Report saved successfully."
                    } else {
                        echo "WARNING: Failed to extract JSON from DAST output."
                    }

                    // Archive only the JSON report
                    archiveArtifacts artifacts: 'dast_report.json', allowEmptyArchive: true
                }
            }
        }

        stage('Cleanup') {
            steps {
                bat 'adb emu kill'
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'apk-outputs/*.apk', allowEmptyArchive: true
        }
    }
}