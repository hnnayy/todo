import groovy.json.JsonSlurperClassic

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
        // 1. Checkout Code
        stage('Checkout') {
            steps {
                echo 'Starting Checkout stage'
                git branch: 'main',
                    url: 'https://github.com/hnnayy/todo.git',
                    credentialsId: 'github-pat-global-test'
            }
        }

        // 2. Persiapan Folder
        stage('Prepare Folders') {
            steps {
                bat 'if not exist apk-outputs mkdir apk-outputs'
                bat "if not exist \"${env.APK_OUTPUT_DIR}\" mkdir \"${env.APK_OUTPUT_DIR}\""
                // Bersihkan folder output eksternal
                bat "del /Q \"${env.APK_OUTPUT_DIR}\\*\""
            }
        }

        // 3. Build APK Debug
        stage('Build Application') {
            steps {
                echo 'Building Flutter APK...'
                bat 'git config --global --add safe.directory C:/flutter'
                bat 'flutter pub get'
                bat 'flutter build apk --debug'
            }
        }

        // 4. SAST Mobile (Static Analysis)
        stage('SAST Mobile') {
            steps {
                script {
                    echo 'Running SAST (Static Analysis)...'
                    
                    // Upload APK ke MobSF
                    def uploadResponse = bat(script: 'curl -s -F "file=@build/app/outputs/flutter-apk/app-debug.apk" http://localhost:8000/api/v1/upload -H "Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac"', returnStdout: true).trim()
                    
                    // Parsing JSON Response untuk ambil HASH
                    def jsonSlurper = new JsonSlurperClassic()
                    def uploadJson = jsonSlurper.parseText(uploadResponse)
                    String apkHash = uploadJson.hash

                    if (!apkHash) {
                        error 'Gagal mendapatkan Hash dari MobSF. Cek koneksi atau file APK.'
                    }

                    echo "APK Hash: ${apkHash}"
                    env.APK_HASH = apkHash

                    // Trigger Scan
                    bat(script: "curl -s -X POST --url http://localhost:8000/api/v1/scan --data \"hash=${apkHash}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()
                    
                    // Ambil Report JSON
                    def reportResponse = bat(script: "curl -s -X POST --url http://localhost:8000/api/v1/report_json --data \"hash=${apkHash}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()
                    
                    // Cek Security Score
                    try {
                        def reportJson = jsonSlurper.parseText(reportResponse)
                        def score = reportJson.security_score
                        echo "Security Score: ${score}/100"
                        
                        if (score < 50) {
                            echo "WARNING: Skor keamanan rendah!"
                        }
                    } catch (Exception e) {
                        echo "Info: Tidak bisa membaca skor otomatis (format JSON mungkin berbeda), tapi report tetap disimpan."
                    }

                    // Simpan Report
                    writeFile file: 'sast_report.json', text: reportResponse
                    archiveArtifacts artifacts: 'sast_report.json', allowEmptyArchive: false
                }
            }
        }

        // 5. Copy APK ke Folder Luar
        stage('Backup APK') {
            steps {
                script {
                    def timestamp = new Date().format("dd-MM-yyyy_HH-mm-ss")
                    def targetPath = "C:\\ApksGenerated\\todo-debug-${timestamp}.apk"
                    bat "copy \"build\\app\\outputs\\flutter-apk\\app-debug.apk\" \"${targetPath}\""
                    env.APK_PATH = targetPath
                }
            }
        }

        // 6. Start Emulator (RAM Ditingkatkan)
        stage('Start Emulator') {
            steps {
                script {
                    def devices = bat(script: "${env.ANDROID_HOME}\\platform-tools\\adb.exe devices", returnStdout: true)
                    if (!devices.contains("emulator")) {
                        echo 'Starting Emulator with 2GB RAM to prevent Lag...'
                        // PERBAIKAN: Menambah -memory 2048
                        bat """
                            start /b "" "${env.ANDROID_HOME}\\emulator\\emulator.exe" -avd "${env.AVD_NAME}" -no-window -no-audio -gpu swiftshader_indirect -wipe-data -memory 2048
                        """
                        echo 'Waiting for emulator startup (60s)...'
                        sleep(time: 60, unit: 'SECONDS')
                        bat "${env.ANDROID_HOME}\\platform-tools\\adb.exe wait-for-device"
                    } else {
                        echo 'Emulator already running.'
                    }
                }
            }
        }

        // 7. Tunggu Booting Selesai
        stage('Wait for Boot') {
            steps {
                script {
                    echo 'Checking boot animation status...'
                    def booted = false
                    for (int i = 0; i < 20; i++) { // Coba 20 kali saja (sekali jalan loop)
                        try {
                            def out = bat(script: 'adb shell getprop init.svc.bootanim', returnStdout: true).trim()
                            if (out.contains("stopped")) {
                                booted = true
                                break
                            }
                        } catch (e) {}
                        sleep(5)
                    }
                    if (!booted) echo "Warning: Emulator might not be fully ready, but proceeding..."
                }
            }
        }

        // 8. Install & Prepare DAST
        stage('Install & Warmup') {
            steps {
                script {
                    echo "Uninstalling old app..."
                    bat(script: "adb uninstall ${env.APP_PACKAGE}", returnStatus: true)
                    
                    echo "Installing new APK..."
                    bat "adb install -r \"${env.APK_PATH}\""

                    // PERBAIKAN PENTING: Istirahat panjang agar Emulator tidak ANR
                    echo "Waiting 60 seconds for App/Emulator to settle before DAST..."
                    sleep(time: 60, unit: 'SECONDS')
                }
            }
        }

        // 9. DAST Mobile (Dynamic Analysis)
        stage('DAST Mobile') {
            steps {
                script {
                    echo 'Starting Dynamic Analysis...'
                    
                    // Start
                    bat(script: "curl -s -X POST --url http://localhost:8000/api/v1/dynamic/start_analysis --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()
                    
                    // Biarkan test berjalan
                    echo "Running Analysis (30s)..."
                    sleep(time: 30, unit: 'SECONDS')

                    // Stop
                    bat(script: "curl -s -X POST --url http://localhost:8000/api/v1/dynamic/stop_analysis --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()
                    
                    // Get Report
                    def dastResponse = bat(script: "curl -s -X POST --url http://localhost:8000/api/v1/dynamic/report_json --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()
                    
                    // Validasi JSON Sederhana
                    try {
                        new JsonSlurperClassic().parseText(dastResponse)
                        echo "DAST Report valid JSON."
                    } catch (e) {
                        echo "Warning: DAST Report might be incomplete."
                    }

                    writeFile file: 'dast_report.json', text: dastResponse
                    archiveArtifacts artifacts: 'dast_report.json', allowEmptyArchive: false
                }
            }
        }

        // 10. Matikan Emulator
        stage('Stop Emulator') {
            steps {
                bat 'adb emu kill'
            }
        }
    }

    post {
        success {
            archiveArtifacts artifacts: 'apk-outputs/*.apk', allowEmptyArchive: true
        }
        always {
            echo 'Pipeline Finished.'
        }
    }
}