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

    parameters {
        choice(name: 'BUILD_TYPE', choices: ['release', 'debug'], description: 'Pilih Tipe Build')
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
                bat "del /Q \"${env.APK_OUTPUT_DIR}\\*\""
            }
        }

        stage('Build Application') {
            steps {
                bat 'git config --global --add safe.directory C:/flutter'
                bat 'flutter pub get'
                bat "flutter build apk --${params.BUILD_TYPE}"
            }
        }

        stage('SAST Mobile') {
            steps {
                script {
                    echo 'Running SAST...'
                    def apkSourcePath = "build/app/outputs/flutter-apk/app-${params.BUILD_TYPE}.apk"
                    
                    def uploadResponse = bat(script: "@curl -s -F \"file=@${apkSourcePath}\" http://localhost:8000/api/v1/upload -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()
                    String apkHash = extractHashFromResponse(uploadResponse)
                    
                    if (apkHash == "") { error "Upload failed." }
                    env.APK_HASH = apkHash
                    echo "SAST Hash: ${apkHash}"

                    bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/scan --data \"hash=${apkHash}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()
                    
                    def rawOutput = bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/report_json --data \"hash=${apkHash}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()

                    String jsonString = cleanJsonString(rawOutput)
                    if (jsonString != null) {
                        writeFile file: 'sast_report.json', text: jsonString
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
                    def sourcePath = "build\\app\\outputs\\flutter-apk\\app-${params.BUILD_TYPE}.apk"
                    def destPath = "apk-outputs\\todo-${params.BUILD_TYPE}-${timestamp}.apk"
                    
                    bat "copy \"${sourcePath}\" \"${destPath}\""
                    env.APK_PATH = destPath
                    
                    bat(script: "adb uninstall ${env.APP_PACKAGE}", returnStatus: true) 
                    bat "adb install -r \"${env.APK_PATH}\""
                }
            }
        }

        // --- DAST STAGE (DENGAN SCREENSHOT) ---
        stage('DAST Mobile') {
            steps {
                script {
                    echo 'Running DAST...'
                    
                    // 1. Force Screen UNLOCK
                    bat "adb shell input keyevent 82" 
                    sleep(time: 2, unit: 'SECONDS')
                    bat "adb shell input keyevent 4" 
                    
                    // 2. START Analysis
                    bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/dynamic/start_analysis --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()
                    
                    echo "Waiting 25s for App Launch..."
                    sleep(time: 25, unit: 'SECONDS') 

                    // 3. ENABLE FRIDA
                    bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/frida/instrument --data \"hash=${env.APK_HASH}&default_hooks=api_monitor,ssl_pinning_bypass,root_bypass,debugger_check_bypass&auxiliary_hooks=&frida_code=\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true)
                    sleep(time: 5, unit: 'SECONDS')

                    // 4. INTERACTION PHASE (Monkey)
                    echo "Running Monkey Testing..."
                    try {
                        bat "adb shell monkey -p ${env.APP_PACKAGE} --pct-syskeys 0 --pct-nav 20 --pct-majornav 20 --pct-touch 50 --throttle 1000 -v 1000"
                    } catch (Exception e) {
                        echo "Monkey finished."
                    }
                    
                    sleep(time: 5, unit: 'SECONDS')

                    // -----------------------------------------------------------
                    // [MODIFIKASI] AMBIL SCREENSHOT AKHIR DAST
                    // -----------------------------------------------------------
                    echo "📸 Taking DAST Screenshot..."
                    // 1. Ambil screenshot di HP (simpan di sdcard)
                    bat "adb shell screencap -p /sdcard/dast_final_screen.png"
                    // 2. Tarik file dari HP ke Jenkins Workspace
                    bat "adb pull /sdcard/dast_final_screen.png dast_final_screen.png"
                    // -----------------------------------------------------------

                    // 5. STOP Analysis
                    bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/dynamic/stop_analysis --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()

                    // 6. Get Report JSON
                    def rawOutput = bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/dynamic/report_json --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()
                    
                    String jsonString = cleanJsonString(rawOutput)
                    if (jsonString != null) {
                        writeFile file: 'dast_report.json', text: jsonString
                    } else {
                        writeFile file: 'dast_raw.txt', text: rawOutput
                    }

                    // Archive JSON dan Gambar Screenshot
                    archiveArtifacts artifacts: 'dast_report.json, dast_final_screen.png', allowEmptyArchive: true
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

            // [MODIFIKASI] AttachmentsPattern ditambah *.png untuk mengirim screenshot
            emailext (
                subject: "Security Report: ${env.JOB_NAME} - #${env.BUILD_NUMBER}",
                body: """<p>Build Selesai.</p>
                         <p><strong>Status Build:</strong> ${currentBuild.currentResult}</p>
                         <hr>
                         <p><strong>Link Laporan MobSF:</strong></p>
                         <ul>
                            <li><a href="http://localhost:8000/static_analyzer/${env.APK_HASH}/">SAST Report</a></li>
                            <li><a href="http://localhost:8000/dynamic_analyzer/${env.APK_HASH}/">DAST Report</a></li>
                         </ul>
                         <p><em>Lihat lampiran untuk Laporan JSON dan <strong>Screenshot Aplikasi</strong> saat test berakhir.</em></p>""",
                to: "mutiahanin2017@gmail.com, gghurl111@gmail.com",
                // 👇 Menambahkan .png agar screenshot terkirim
                attachmentsPattern: "**/*.json, **/*.png"
            )
        }
    }
}