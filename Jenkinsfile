import groovy.json.JsonSlurperClassic 

// --- BAGIAN 1: Helper Methods (NonCPS) ---
// Kita pisahkan logika Regex di sini agar tidak menyebabkan error "NotSerializableException"
// Jenkins tidak akan mencoba menyimpan state variabel di dalam method @NonCPS.

@NonCPS
def extractHashFromResponse(String response) {
    def matcher = response =~ /"hash"\s*:\s*"([^"]+)"/
    if (matcher.find()) {
        return matcher.group(1)
    }
    return ""
}

@NonCPS
def extractScoreFromResponse(String response) {
    def matcher = response =~ /"security_score"\s*:\s*(\d+)/
    if (matcher.find()) {
        return matcher.group(1).toInteger()
    }
    return 0
}

@NonCPS
def parseJsonSafely(String jsonText) {
    // Fungsi ini membungkus JsonSlurper agar lebih aman dipanggil
    try {
        def slurper = new JsonSlurperClassic()
        return slurper.parseText(jsonText)
    } catch (Exception e) {
        return null
    }
}
// ------------------------------------------

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
        // Checkout code
        stage('Checkout') {
            steps {
                echo 'Starting Checkout stage'
                git branch: 'main',
                    url: 'https://github.com/hnnayy/todo.git',
                    credentialsId: 'github-pat-global-test'
                echo 'Checkout completed successfully'
            }
        }

        // Prepare folders
        stage('Prepare Destination Folders') {
            steps {
                bat 'if not exist apk-outputs mkdir apk-outputs'
                bat "if not exist \"${env.APK_OUTPUT_DIR}\" mkdir \"${env.APK_OUTPUT_DIR}\""
            }
        }

        // Clean output folder
        stage('Clean Folder C:\\ApksGenerated') {
            steps {
                bat "del /Q \"${env.APK_OUTPUT_DIR}\\*\""
            }
        }

        // Build Debug APK
        stage('Build Application') {
            steps {
                echo 'Starting Build Application stage'
                bat 'git config --global --add safe.directory C:/flutter'
                bat 'flutter pub get'
                bat 'flutter build apk --debug'
                echo 'Build Application completed successfully'
            }
        }

        // SAST Mobile using MobSF (FIXED SERIALIZATION ERROR)
        stage('SAST Mobile') {
            steps {
                script {
                    echo 'Running Static Application Security Testing (SAST) using MobSF'
                    
                    // 1. Upload APK
                    def uploadResponse = bat(script: 'curl -s -F "file=@build/app/outputs/flutter-apk/app-debug.apk" http://localhost:8000/api/v1/upload -H "Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac"', returnStdout: true).trim()
                    
                    // MENGGUNAKAN METHOD @NonCPS (Aman dari error Serialization)
                    String apkHash = extractHashFromResponse(uploadResponse)

                    if (apkHash == "") {
                        error "Failed to parse hash. Response: ${uploadResponse}"
                    }

                    echo "APK uploaded with hash: ${apkHash}"
                    env.APK_HASH = apkHash

                    // 2. Scan APK
                    bat(script: "curl -s -X POST --url http://localhost:8000/api/v1/scan --data \"hash=${apkHash}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()
                    echo "Scan completed."

                    // 3. Get JSON Report
                    def reportResponse = bat(script: "curl -s -X POST --url http://localhost:8000/api/v1/report_json --data \"hash=${apkHash}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()
                    writeFile file: 'sast_report.json', text: reportResponse
                    echo "SAST JSON Report saved."

                    // 4. Try Get PDF Report (Robust Handling)
                    echo "Attempting to download PDF Report..."
                    // Download ke file sementara
                    bat(script: "curl -s -X POST --url http://localhost:8000/api/v1/download_pdf --data \"hash=${apkHash}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\" -o sast_report_temp.pdf")
                    
                    // Cek isi file apakah PDF valid atau error text
                    def pdfContent = readFile('sast_report_temp.pdf')
                    
                    // Jika file mengandung kata "wkhtmltopdf", berarti error dari server
                    if (pdfContent.contains("wkhtmltopdf") || pdfContent.contains("Cannot Generate PDF")) {
                        echo "=================================================================================="
                        echo "WARNING: MobSF gagal membuat PDF. Mengaktifkan FALLBACK MODE (HTML)."
                        echo "PENTING: Anda harus menginstall wkhtmltopdf di server MobSF untuk fix permanen."
                        echo "=================================================================================="
                        
                        // --- FALLBACK: GENERATE HTML FROM JSON ---
                        // Menggunakan helper method @NonCPS untuk parsing JSON
                        def json = parseJsonSafely(reportResponse)
                        
                        if (json != null) {
                            def score = json.security_score ?: 0
                            def appName = json.app_name ?: "Unknown App"
                            
                            def htmlContent = """
                            <html>
                            <head><style>body{font-family:Arial;} .card{border:1px solid #ddd;padding:20px;margin:20px;}</style></head>
                            <body>
                                <div class="card">
                                    <h1>MobSF Security Report</h1>
                                    <p><b>App Name:</b> ${appName}</p>
                                    <p><b>Security Score:</b> ${score}/100</p>
                                    <hr>
                                    <p><i>PDF Report failed to generate. Please check sast_report.json for details.</i></p>
                                </div>
                            </body>
                            </html>
                            """
                            writeFile file: 'sast_report.html', text: htmlContent
                            echo "Fallback HTML generated."
                            bat "del sast_report_temp.pdf" // Hapus file error
                        } else {
                            echo "Gagal parsing JSON untuk Fallback HTML."
                        }
                    } else {
                        echo "PDF generated successfully."
                        bat "move sast_report_temp.pdf sast_report.pdf"
                    }

                    // Score Check Logic (Menggunakan @NonCPS method)
                    Integer scoreVal = extractScoreFromResponse(reportResponse)
                    
                    if (scoreVal < 10) {
                         echo "Security Score is: ${scoreVal}"
                    }
                    if (scoreVal < 50) {
                        echo 'Warning: Low Security Score detected!'
                    }

                    // Archive artifacts
                    archiveArtifacts artifacts: 'sast_report.json, sast_report.pdf, sast_report.html', allowEmptyArchive: true
                }
            }
        }

        // Verify Generated APK
        stage('Verify Generated APK') {
            steps {
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

        // Copy APK to C:\ApksGenerated
        stage('Copy APK to C:\\ApksGenerated') {
            steps {
                script {
                    def timestamp = new Date().format("dd-MM-yyyy_HH-mm-ss")
                    echo "Copying APK to C:\\ApksGenerated with timestamp ${timestamp}"
                    bat """
                        copy "build\\app\\outputs\\flutter-apk\\app-debug.apk" "C:\\ApksGenerated\\todo-debug-${timestamp}.apk"
                    """
                    env.APK_PATH = "C:\\ApksGenerated\\todo-debug-${timestamp}.apk"
                }
            }
        }

        // Start Emulator
        stage('Start Emulator') {
            steps {
                script {
                    def emulatorStatus = bat(script: "${env.ANDROID_HOME}\\platform-tools\\adb.exe devices", returnStdout: true)
                    if (!emulatorStatus.contains("emulator")) {
                        echo 'Starting Android emulator...'
                        bat """
                            start /b "" "${env.ANDROID_HOME}\\emulator\\emulator.exe" -avd "${env.AVD_NAME}" -no-window -no-audio -gpu swiftshader_indirect -wipe-data
                        """
                        echo 'Waiting for emulator...'
                        sleep(time: 60, unit: 'SECONDS')
                        bat "${env.ANDROID_HOME}\\platform-tools\\adb.exe wait-for-device"
                    } else {
                        echo 'Emulator is already running.'
                    }
                }
            }
        }

        // Wait for Boot
        stage('Wait for Emulator to Boot') {
            steps {
                script {
                    echo 'Waiting for boot animation...'
                    sleep(time: 15, unit: 'SECONDS')
                    try {
                        bat 'adb shell getprop init.svc.bootanim'
                    } catch (Exception e) {
                        echo "Warning: Checking bootanim failed, proceeding anyway..."
                    }
                }
            }
        }

        // Install APK
        stage('Install APK on Emulator') {
            steps {
                script {
                    bat(script: "adb uninstall ${env.APP_PACKAGE}", returnStatus: true) 
                    bat "adb install -r \"${env.APK_PATH}\""
                }
            }
        }

        // DAST Mobile (MobSF)
        stage('DAST Mobile') {
            steps {
                script {
                    echo 'Running Dynamic Analysis...'
                    // Start
                    bat(script: "curl -s -X POST --url http://localhost:8000/api/v1/dynamic/start_analysis --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()
                    
                    sleep(time: 30, unit: 'SECONDS') 

                    // Stop
                    bat(script: "curl -s -X POST --url http://localhost:8000/api/v1/dynamic/stop_analysis --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()

                    // Get JSON Report
                    def dastReportResponse = bat(script: "curl -s -X POST --url http://localhost:8000/api/v1/dynamic/report_json --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()
                    
                    writeFile file: 'dast_report.json', text: dastReportResponse
                    
                    // Cek validitas JSON DAST menggunakan helper method @NonCPS
                    def jsonCheck = parseJsonSafely(dastReportResponse)
                    if (jsonCheck != null) {
                        echo "DAST Report JSON valid."
                    } else {
                         echo "Warning: DAST JSON might be incomplete."
                    }

                    archiveArtifacts artifacts: 'dast_report.json', allowEmptyArchive: false
                }
            }
        }

        // Verify Installed
        stage('Verify Installed APK') {
            steps {
                bat """
                    adb shell pm list packages | findstr "${env.APP_PACKAGE}"
                """
            }
        }

        // Environment Prep
        stage('Prepare Environment') {
            steps {
                bat 'adb shell settings put global window_animation_scale 0'
                bat 'adb shell settings put global transition_animation_scale 0'
                bat 'adb shell settings put global animator_duration_scale 0'
            }
        }

        // Tests
        stage('Run Tests') {
            steps {
                echo 'Skipping flutter test command (placeholder)'
            }
        }

        // HTML Report
        stage('Publish Test Report (HTML)') {
            steps {
                publishHTML(target: [
                    allowMissing: true,
                    alwaysLinkToLastBuild: true,
                    keepAll: true,
                    reportDir: 'build/reports/tests/testDebugUnitTest', 
                    reportFiles: 'index.html',
                    reportName: 'Flutter Test Report'
                ])
            }
        }

        // Release Build
        stage('Build APK Release') {
            when {
                expression { currentBuild.result == null || currentBuild.result == 'SUCCESS' }
            }
            steps {
                bat 'flutter build apk --release'
            }
        }

        // Clean & Archive
        stage('Clean APK Outputs') {
            steps {
                bat 'if exist apk-outputs\\* del /Q apk-outputs\\*'
            }
        }

        stage('Copy APK to apk-outputs') {
            steps {
                script {
                    def timestamp = new Date().format("dd-MM-yyyy_HH-mm-ss")
                    bat """
                        copy "build\\app\\outputs\\flutter-apk\\app-debug.apk" "apk-outputs\\todo-debug-${timestamp}.apk"
                    """
                }
            }
        }

        // Stop Emulator
        stage('Stop Emulator') {
            steps {
                bat 'adb emu kill'
            }
        }
    }

    post {
        success {
            archiveArtifacts artifacts: 'apk-outputs/todo-debug-*.apk', allowEmptyArchive: true
            archiveArtifacts artifacts: 'build/app/outputs/flutter-apk/app-release.apk', allowEmptyArchive: true
        }
        failure {
            echo 'Build failed.'
        }
        always {
            echo 'Pipeline completed'
        }
    }
}