import groovy.json.JsonSlurperClassic 

// --- HELPER METHODS ---

@NonCPS
def extractHashFromResponse(String response) {
    def matcher = response =~ /"hash"\s*:\s*"([^"]+)"/
    if (matcher.find()) {
        return matcher.group(1)
    }
    return ""
}

@NonCPS
def cleanJsonString(String rawOutput) {
    int firstBrace = rawOutput.indexOf('{')
    int lastBrace = rawOutput.lastIndexOf('}')
    if (firstBrace == -1 || lastBrace == -1) { return null }
    return rawOutput.substring(firstBrace, lastBrace + 1)
}

// -----------------------------------------------------------------------

pipeline {
    agent any

    // [MODIFIKASI] Menambahkan Parameter Pilihan
    parameters {
        choice(name: 'BUILD_TYPE', choices: ['release', 'debug'], description: 'Pilih Tipe Build (Gunakan Release untuk hasil audit yang akurat)')
    }

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

        stage('Clean Folder C:\\ApksGenerated') {
            steps {
                echo "Cleaning ${env.APK_OUTPUT_DIR} folder."
                bat "del /Q \"${env.APK_OUTPUT_DIR}\\*\""
            }
        }

        stage('Build Application') {
            steps {
                echo "Starting Build Application stage (Mode: ${params.BUILD_TYPE})"
                bat 'git config --global --add safe.directory C:/flutter'
                bat 'flutter pub get'
                // [MODIFIKASI] Command build dinamis sesuai parameter
                bat "flutter build apk --${params.BUILD_TYPE}"
            }
        }

        // --- SAST STAGE ---
        stage('SAST Mobile') {
            steps {
                script {
                    echo 'Running SAST...'
                    
                    // [MODIFIKASI] Path file dinamis (app-release.apk atau app-debug.apk)
                    def apkSourcePath = "build/app/outputs/flutter-apk/app-${params.BUILD_TYPE}.apk"
                    
                    // Upload ke MobSF
                    def uploadResponse = bat(script: "@curl -s -F \"file=@${apkSourcePath}\" http://localhost:8000/api/v1/upload -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()
                    String apkHash = extractHashFromResponse(uploadResponse)
                    
                    if (apkHash == "") { error "Upload failed." }
                    env.APK_HASH = apkHash
                    echo "SAST Hash: ${apkHash}"

                    // Scan
                    bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/scan --data \"hash=${apkHash}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()
                    
                    // Get Report
                    def rawOutput = bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/report_json --data \"hash=${apkHash}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()

                    String jsonString = cleanJsonString(rawOutput)
                    if (jsonString != null) {
                        writeFile file: 'sast_report.json', text: jsonString
                        echo "SAST JSON Report saved."
                        echo "✅ SAST Report URL: http://localhost:8000/static_analyzer/${apkHash}/"
                    }
                    archiveArtifacts artifacts: 'sast_report.json', allowEmptyArchive: true
                }
            }
        }

        stage('Setup Emulator') {
            steps {
                script {
                    def devices = bat(script: "adb devices", returnStdout: true)
                    if (!devices.contains("emulator")) {
                        // [PENTING] -gpu swiftshader_indirect mencegah crash pada Flutter Impeller
                        echo "Starting emulator with software rendering to prevent Impeller crash..."
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
                    
                    // [MODIFIKASI] Copy file yang benar (Release/Debug)
                    def sourcePath = "build\\app\\outputs\\flutter-apk\\app-${params.BUILD_TYPE}.apk"
                    def destPath = "apk-outputs\\todo-${params.BUILD_TYPE}-${timestamp}.apk"
                    
                    echo "Copying APK from ${sourcePath} to ${destPath}"
                    bat "copy \"${sourcePath}\" \"${destPath}\""
                    
                    env.APK_PATH = destPath
                    
                    bat(script: "adb uninstall ${env.APP_PACKAGE}", returnStatus: true) 
                    bat "adb install -r \"${env.APK_PATH}\""
                }
            }
        }

        // --- DAST STAGE (HEAVY DUTY) ---
        stage('DAST Mobile') {
            steps {
                script {
                    echo 'Running DAST with Advanced Instrumentation...'
                    
                    // 1. Force Screen UNLOCK (Mengatasi Injection Failed)
                    echo "Unlocking screen..."
                    bat "adb shell input keyevent 82" 
                    sleep(time: 2, unit: 'SECONDS')
                    bat "adb shell input keyevent 4" 
                    
                    // 2. START Analysis
                    bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/dynamic/start_analysis --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()
                    
                    echo "Waiting 25s for App Launch..."
                    sleep(time: 25, unit: 'SECONDS') 

                    // 3. ENABLE FRIDA
                    echo "Injecting Frida Hooks..."
                    bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/frida/instrument --data \"hash=${env.APK_HASH}&default_hooks=api_monitor,ssl_pinning_bypass,root_bypass,debugger_check_bypass&auxiliary_hooks=&frida_code=\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true)
                    
                    sleep(time: 5, unit: 'SECONDS')

                    // 4. INTERACTION PHASE
                    echo "Starting Hybrid Interaction..."

                    // A. Logical Input
                    try {
                        bat "adb shell input keyevent 61" // Tab
                        bat "adb shell input text \"TEST\"" 
                        bat "adb shell input keyevent 66" // Enter
                    } catch (Exception e) { echo "Input skipped" }

                    // B. Monkey Testing (OPTIMIZED FOR SPEED)
                    echo "Running Monkey (Fast Mode)..."
                    try {
                        // [MODIFIKASI] Throttle 1500 (1.5 detik) agar stabil, dan count 200 agar durasi cepat selesai (sekitar 5 menit total)
                        bat "adb shell monkey -p ${env.APP_PACKAGE} --pct-syskeys 0 --pct-nav 20 --pct-majornav 20 --pct-touch 50 --throttle 1500 -v 200"
                    } catch (Exception e) {
                        echo "Monkey finished."
                    }

                    sleep(time: 15, unit: 'SECONDS') 

                    // --- [BARU] 5. TLS/SSL SECURITY TEST ---
                    // Mengambil laporan TLS/SSL Security Tester
                    echo "Running TLS/SSL Security Tests..."
                    def tlsRaw = bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/android/tls_tests --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()
                    
                    String tlsJson = cleanJsonString(tlsRaw)
                    if (tlsJson != null) {
                        writeFile file: 'tls_report.json', text: tlsJson
                        echo "✅ TLS Report Saved."
                    }

                    // --- [BARU] 6. GET FRIDA LOGS (RAW) ---
                    // Mengambil Frida Log output
                    echo "Fetching Frida Logs..."
                    def fridaLogsRaw = bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/frida/logs --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()

                    String fridaLogsJson = cleanJsonString(fridaLogsRaw)
                    if (fridaLogsJson != null) {
                        writeFile file: 'frida_logs.json', text: fridaLogsJson
                        echo "✅ Frida Logs Saved."
                    }

                    // --- [BARU] 7. GET FRIDA API MONITOR (VIEW) ---
                    // Mengambil data API Monitor untuk 'view' yang lebih detail
                    echo "Fetching Frida API Monitor Data..."
                    def fridaMonitorRaw = bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/frida/api_monitor --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()

                    String fridaMonitorJson = cleanJsonString(fridaMonitorRaw)
                    if (fridaMonitorJson != null) {
                        writeFile file: 'frida_monitor.json', text: fridaMonitorJson
                        echo "✅ Frida API Monitor Saved."
                    }

                    // 8. STOP Analysis
                    bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/dynamic/stop_analysis --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()

                    // 9. Get JSON Report
                    def rawOutput = bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/dynamic/report_json --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()

                    String jsonString = cleanJsonString(rawOutput)
                    
                    if (jsonString != null) {
                        writeFile file: 'dast_report.json', text: jsonString
                        echo "DAST JSON Report saved successfully."
                        echo "✅ DAST Report URL: http://localhost:8000/dynamic_analyzer/${env.APK_HASH}/"
                    } else {
                        echo "WARNING: Failed to extract JSON from DAST output."
                        writeFile file: 'dast_raw.txt', text: rawOutput
                    }

                    // [BARU] Simpan semua report baru ke Artifacts
                    archiveArtifacts artifacts: 'dast_report.json, tls_report.json, frida_logs.json, frida_monitor.json', allowEmptyArchive: true
                }
            }
        }

        stage('Cleanup') {
            steps {
                bat 'taskkill /F /IM qemu-system-x86_64.exe /T || echo Emulator already stopped'
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'apk-outputs/*.apk', allowEmptyArchive: true

            // [MODIFIKASI] Mengirim Email dengan Lampiran Report Lengkap
            emailext (
                subject: "Laporan Security Scan Mobile App: ${env.JOB_NAME} - #${env.BUILD_NUMBER}",
                body: """<p>Build Selesai. Berikut detail laporan scan keamanan:</p>
                         <p><strong>Status Build:</strong> ${currentBuild.currentResult}</p>
                         <hr>
                         <p><strong>🔗 Link Laporan MobSF (Localhost):</strong></p>
                         <ul>
                           <li><strong>SAST Report (Static):</strong> <a href="http://localhost:8000/static_analyzer/${env.APK_HASH}/">Lihat Laporan SAST</a></li>
                           <li><strong>DAST Report (Dynamic):</strong> <a href="http://localhost:8000/dynamic_analyzer/${env.APK_HASH}/">Lihat Laporan DAST</a></li>
                         </ul>
                         <p><em>File JSON lengkap (SAST, DAST, TLS Report, Frida Logs, & API Monitor) telah dilampirkan pada email ini.</em></p>""",
                to: "mutiahanin2017@gmail.com, gghurl111@gmail.com",
                attachmentsPattern: "**/*.json"
            )
        }
    }
}