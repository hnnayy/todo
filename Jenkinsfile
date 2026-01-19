import groovy.json.JsonSlurperClassic

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
        // 1. Checkout Code
        stage('Checkout') {
            steps {
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

        // 4. SAST Mobile (Metode File - Anti Error "Reading C")
        stage('SAST Mobile') {
            steps {
                script {
                    echo 'Running SAST Upload...'
                    
                    // -- LANGKAH 1: Upload APK dan simpan output ke file --
                    // Kita gunakan -o untuk menyimpan respon ke file 'sast_upload.json' agar output command prompt tidak ikut terbaca
                    bat 'curl -s -F "file=@build/app/outputs/flutter-apk/app-debug.apk" -o sast_upload.json http://localhost:8000/api/v1/upload -H "Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac"'
                    
                    // Baca file hasil upload
                    def uploadJson = new JsonSlurperClassic().parseText(readFile('sast_upload.json').trim())
                    String apkHash = uploadJson.hash

                    if (!apkHash) {
                        error 'Gagal mendapatkan Hash. Cek file sast_upload.json di workspace.'
                    }
                    echo "APK Hash: ${apkHash}"
                    env.APK_HASH = apkHash

                    // -- LANGKAH 2: Trigger Scan --
                    echo 'Scanning...'
                    bat "curl -s -X POST -o sast_scan.json --url http://localhost:8000/api/v1/scan --data \"hash=${apkHash}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\""
                    
                    // -- LANGKAH 3: Ambil Report --
                    echo 'Getting Report...'
                    bat "curl -s -X POST -o sast_report.json --url http://localhost:8000/api/v1/report_json --data \"hash=${apkHash}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\""
                    
                    // Baca skor (Optional)
                    try {
                        def reportJson = new JsonSlurperClassic().parseText(readFile('sast_report.json').trim())
                        echo "Security Score: ${reportJson.security_score}/100"
                    } catch (e) {
                        echo "Info: Tidak bisa membaca skor otomatis, tapi report aman tersimpan."
                    }

                    // Archive Artifacts
                    archiveArtifacts artifacts: 'sast_report.json', allowEmptyArchive: false
                }
            }
        }

        // 5. Backup APK
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

        // 6. Start Emulator (RAM 2GB)
        stage('Start Emulator') {
            steps {
                script {
                    def devices = bat(script: "${env.ANDROID_HOME}\\platform-tools\\adb.exe devices", returnStdout: true)
                    if (!devices.contains("emulator")) {
                        echo 'Starting Emulator...'
                        // Menggunakan -memory 2048 agar tidak lag
                        bat """
                            start /b "" "${env.ANDROID_HOME}\\emulator\\emulator.exe" -avd "${env.AVD_NAME}" -no-window -no-audio -gpu swiftshader_indirect -wipe-data -memory 2048
                        """
                        echo 'Waiting for emulator startup (60s)...'
                        sleep(time: 60, unit: 'SECONDS')
                        bat "${env.ANDROID_HOME}\\platform-tools\\adb.exe wait-for-device"
                    }
                }
            }
        }

        // 7. Install & Warmup
        stage('Install & Warmup') {
            steps {
                script {
                    echo "Uninstalling old app..."
                    bat(script: "adb uninstall ${env.APP_PACKAGE}", returnStatus: true)
                    
                    echo "Installing new APK..."
                    bat "adb install -r \"${env.APK_PATH}\""

                    echo "Waiting 60 seconds for App to settle..."
                    sleep(time: 60, unit: 'SECONDS')
                }
            }
        }

        // 8. DAST Mobile (Metode File)
        stage('DAST Mobile') {
            steps {
                script {
                    echo 'Starting Dynamic Analysis...'
                    
                    // Start Analysis (Output ke file dummy biar bersih)
                    bat "curl -s -X POST -o dast_start.log --url http://localhost:8000/api/v1/dynamic/start_analysis --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\""
                    
                    echo "Running Analysis (30s)..."
                    sleep(time: 30, unit: 'SECONDS')

                    // Stop Analysis
                    bat "curl -s -X POST -o dast_stop.log --url http://localhost:8000/api/v1/dynamic/stop_analysis --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\""
                    
                    // Get Report & Save to File
                    echo "Downloading DAST Report..."
                    bat "curl -s -X POST -o dast_report.json --url http://localhost:8000/api/v1/dynamic/report_json --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\""
                    
                    // Validasi JSON
                    try {
                        new JsonSlurperClassic().parseText(readFile('dast_report.json').trim())
                        echo "DAST Report valid."
                    } catch (e) {
                        echo "Warning: DAST Report incomplete."
                    }

                    archiveArtifacts artifacts: 'dast_report.json', allowEmptyArchive: false
                }
            }
        }

        // 9. Stop Emulator
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