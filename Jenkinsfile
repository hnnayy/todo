import groovy.json.JsonSlurperClassic 

// --- HELPER METHODS ---

@NonCPS
def extractHashFromResponse(String response) {
    // Mengekstrak hash unik dari response JSON upload [cite: 84]
    def matcher = response =~ /"hash"\s*:\s*"([^"]+)"/
    if (matcher.find()) {
        return matcher.group(1)
    }
    return ""
}

@NonCPS
def cleanJsonString(String rawOutput) {
    // Membersihkan output agar menjadi format JSON yang valid untuk disimpan [cite: 83, 105]
    int firstBrace = rawOutput.indexOf('{')
    int lastBrace = rawOutput.lastIndexOf('}')
    if (firstBrace == -1 || lastBrace == -1) { return null }
    return rawOutput.substring(firstBrace, lastBrace + 1)
}

// -----------------------------------------------------------------------

pipeline {
    agent any

    parameters {
        choice(name: 'BUILD_TYPE', choices: ['release', 'debug'], description: 'Pilih Tipe Build (Gunakan Release untuk hasil audit yang akurat)')
    }

    environment {
        ANDROID_HOME = "C:\\Users\\SECULAB\\AppData\\Local\\Android\\Sdk"
        PATH = "${env.ANDROID_HOME}\\tools;${env.ANDROID_HOME}\\platform-tools;${env.PATH}"
        AVD_NAME = "Pixel_4_XL_2"
        APP_PACKAGE = "com.example.mobileapp" 
        APK_OUTPUT_DIR = "C:\\ApksGenerated"
        // API Key sesuai lampiran dokumentasi [cite: 4]
        API_KEY = "fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac"
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

        stage('Clean Folder APK') {
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
                bat "flutter build apk --${params.BUILD_TYPE}"
            }
        }

        stage('MobSF - Static Analysis') {
            steps {
                script {
                    echo 'Running SAST Mobile...'
                    def apkSourcePath = "build/app/outputs/flutter-apk/app-${params.BUILD_TYPE}.apk"
                    
                    // 1. API: Upload a File [cite: 73, 75]
                    echo "Uploading APK to MobSF..."
                    def uploadRes = bat(script: "@curl -s -F \"file=@${apkSourcePath}\" http://localhost:8000/api/v1/upload -H \"Authorization: ${env.API_KEY}\"", returnStdout: true).trim()
                    env.APK_HASH = extractHashFromResponse(uploadRes)
                    
                    if (env.APK_HASH == "") { error "Upload Gagal! Periksa koneksi ke MobSF." }
                    echo "APK Hash: ${env.APK_HASH}"

                    // 2. API: Scan a File [cite: 96, 98]
                    echo "Initiating Static Scan..."
                    bat "@curl -s -X POST --url http://localhost:8000/api/v1/scan --data \"hash=${env.APK_HASH}\" -H \"Authorization: ${env.API_KEY}\""

                    // 3. API: Generate JSON Report [cite: 259, 261]
                    echo "Downloading Static Analysis JSON Report..."
                    def staticReport = bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/report_json --data \"hash=${env.APK_HASH}\" -H \"Authorization: ${env.API_KEY}\"", returnStdout: true).trim()
                    writeFile file: 'static_report.json', text: cleanJsonString(staticReport)

                    // 4. API: Display Recent Scans [cite: 311, 313]
                    echo "Fetching Recent Scans list..."
                    def recent = bat(script: "@curl -s -G http://localhost:8000/api/v1/scans --data-urlencode \"page=1\" --data-urlencode \"page_size=5\" -H \"Authorization: ${env.API_KEY}\"", returnStdout: true).trim()
                    writeFile file: 'recent_scans.json', text: cleanJsonString(recent)
                }
            }
        }

        stage('Setup Emulator') {
            steps {
                script {
                    def devices = bat(script: "adb devices", returnStdout: true)
                    if (!devices.contains("emulator")) {
                        echo "Starting Android Emulator (${env.AVD_NAME})..."
                        bat "start /b \"\" \"${env.ANDROID_HOME}\\emulator\\emulator.exe\" -avd \"${env.AVD_NAME}\" -no-window -no-audio -gpu swiftshader_indirect -wipe-data"
                        sleep(time: 60, unit: 'SECONDS')
                        bat "adb wait-for-device"
                    }
                }
            }
        }

        stage('Install & MobSFy Android') {
            steps {
                script {
                    echo "Installing APK to Emulator..."
                    bat "adb install -r build/app/outputs/flutter-apk/app-${params.BUILD_TYPE}.apk"
                    
                    // Unlock Screen
                    bat "adb shell input keyevent 82"
                    
                    // API: MobSFy runtime environment [cite: 557, 559]
                    echo "MobSFying the device environment..."
                    bat "@curl -s -X POST --url http://localhost:8000/api/v1/android/mobsfy --data \"identifier=emulator-5554\" -H \"Authorization: ${env.API_KEY}\""
                }
            }
        }

        stage('MobSF - DAST & Advanced Extraction') {
            steps {
                script {
                    echo "Starting Dynamic Analysis..."
                    
                    // 5. API: Start Dynamic Analysis [cite: 512, 513]
                    bat "@curl -s -X POST --url http://localhost:8000/api/v1/dynamic/start_analysis --data \"hash=${env.APK_HASH}\" -H \"Authorization: ${env.API_KEY}\""
                    
                    echo "Waiting for app to initialize and run interactions..."
                    sleep(time: 40, unit: 'SECONDS') 

                    // 6. API: Dynamic JSON Report (Untuk TRACKERS & BASE64 STRINGS) [cite: 889, 891]
                    echo "Extracting Trackers and Decoded Base64 Strings..."
                    def dynamicReport = bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/dynamic/report_json --data \"hash=${env.APK_HASH}\" -H \"Authorization: ${env.API_KEY}\"", returnStdout: true).trim()
                    writeFile file: 'trackers_base64_report.json', text: cleanJsonString(dynamicReport)

                    // 7. API: View Source - XML FILES Extraction [cite: 910, 913]
                    echo "Fetching XML/Preferences Files..."
                    def xmlData = bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/dynamic/view_source --data \"file=data/data/${env.APP_PACKAGE}/shared_prefs/&hash=${env.APK_HASH}&type=xml\" -H \"Authorization: ${env.API_KEY}\"", returnStdout: true).trim()
                    writeFile file: 'dynamic_xml_files.json', text: cleanJsonString(xmlData)

                    // 8. API: View Source - SQLITE DATABASE Extraction [cite: 910, 913]
                    echo "Fetching SQLite Database Data..."
                    def dbData = bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/dynamic/view_source --data \"file=data/data/${env.APP_PACKAGE}/databases/&hash=${env.APK_HASH}&type=db\" -H \"Authorization: ${env.API_KEY}\"", returnStdout: true).trim()
                    writeFile file: 'dynamic_sqlite_db.json', text: cleanJsonString(dbData)

                    // 9. API: Stop Dynamic Analysis [cite: 864, 866]
                    echo "Stopping Dynamic Analysis..."
                    bat "@curl -s -X POST --url http://localhost:8000/api/v1/dynamic/stop_analysis --data \"hash=${env.APK_HASH}\" -H \"Authorization: ${env.API_KEY}\""
                }
            }
        }

        stage('Cleanup') {
            steps {
                echo "Stopping Emulator..."
                bat 'taskkill /F /IM qemu-system-x86_64.exe /T || echo Emulator already stopped'
            }
        }
    }

    post {
        always {
            // Mengarsipkan semua hasil ekstraksi JSON sebagai Artifacts
            archiveArtifacts artifacts: '*.json', allowEmptyArchive: true
            
            echo "Sending Security Reports via Email..."
            emailext (
                subject: "Laporan Security Scan Mobile: ${env.JOB_NAME} - #${env.BUILD_NUMBER}",
                to: "mutiahanin2017@gmail.com, gghurl111@gmail.com",
                body: """<p>Build Selesai. Data keamanan berikut telah berhasil diekstrak secara terpisah:</p>
                         <ul>
                            <li><strong>XML Files:</strong> Terlampir (dynamic_xml_files.json)</li>
                            <li><strong>SQLite Database:</strong> Terlampir (dynamic_sqlite_db.json)</li>
                            <li><strong>Trackers & Base64 Strings:</strong> Terlampir (trackers_base64_report.json)</li>
                         </ul>
                         <p>Laporan Interaktif: <a href="http://localhost:8000/dynamic_analyzer/${env.APK_HASH}/">Buka MobSF DAST</a></p>""",
                attachmentsPattern: "*.json"
            )
        }
    }
}