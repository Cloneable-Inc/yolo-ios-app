import ReplayKit
import UIKit
import AVFoundation
import CoreML
import CoreMedia
import YOLO
import AudioToolbox

// MARK: - ModelEntry
// Identical to your original struct or class for model definitions.
// We keep it in MainViewController or a separate file if you prefer.


// MARK: - MainViewController
class MainViewController: UIViewController {

    // MARK: - IBOutlets (from Storyboard)
    @IBOutlet weak var View0: UIView!
    @IBOutlet weak var segmentedControl: UISegmentedControl!
    @IBOutlet weak var labelName: UILabel!
    @IBOutlet weak var labelFPS: UILabel!
    @IBOutlet weak var labelVersion: UILabel!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var forcus: UIImageView!
    @IBOutlet weak var logoImage: UIImageView!
    
    // If you have more IBOutlets (e.g., for other labels, sliders), keep them all here:
    // @IBOutlet weak var someSlider: UISlider!
    // ...

    // MARK: - UI Elements (Programmatic, if any)
    // (Share/Record buttons remain here, as in your original code)
    var shareButton = UIButton()
    var recordButton = UIButton()
    let selection = UISelectionFeedbackGenerator()
    
    // MARK: - Data/Logic for tasks/models
    // Identical arrays/dictionaries from original code
    private let tasks: [(name: String, folder: String)] = [
        ("Classify", "ClassifyModels"), // index 0
        ("Segment",  "SegmentModels"),  // index 1
        ("Detect",   "DetectModels"),   // index 2
        ("Pose",     "PoseModels"),     // index 3
        ("Obb",      "ObbModels"),      // index 4
    ]
    private var modelsForTask: [String: [String]] = [:]
    
    // Suppose you also had some dictionary of remote models, e.g.:
    // var remoteModelsInfo: [String: [(String, URL)]] = ...
    // We keep it the same. If it was originally in your code,
    // ensure it’s accessible here or wherever you had it:
   
    
    private var currentModels: [ModelEntry] = []
    private var selectedIndexPath: IndexPath?
    private var currentTask: String = ""
    
    // This table is purely for selecting models in the iPhone UI
    private let modelTableView: UITableView = {
        let table = UITableView()
        table.isHidden = true
        table.layer.cornerRadius = 8
        table.clipsToBounds = true
        return table
    }()
    
    private let tableViewBGView = UIView()
    
    // MARK: - External Display
    // We'll hold a reference to the external view controller
    // so we can notify it about tasks or model selections.
    weak var externalVC: ExternalDisplayViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 1. Setup tasks in segmented control
        setupTaskSegmentedControl()
        
        // 2. Preload local model file names for each task
        loadModelsForAllTasks()
        
        // 3. Default selected segment (example: "Detect" at index 2)
        if tasks.indices.contains(2) {
            segmentedControl.selectedSegmentIndex = 2
            currentTask = tasks[2].name
            reloadModelEntries(for: currentTask)
        }

        // 4. Setup the model table
        setupTableView()
        
        // 5. Setup share/record buttons
        setupButtons()
        
        // 6. Additional UI setup if needed
        // ...
        
        // 7. Some example setup for your labelVersion, etc.
        labelVersion.text = "v1.0"
        
        // 8. If you are using a progress view or label for download,
        //    you can keep them here or in the external VC.
        //    In your original code, you had them in the same file,
        //    but you can keep them if you like. For demonstration:
        //    (If you want to keep them in the main iPhone UI, do so.)
        //    If you want them in the external side, move them there.
        
        // ...
        
        // 9. Example: if you already discovered an external screen, you’d instantiate
        //    and store externalVC. Usually done in SceneDelegate, but shown here as reference:
        /*
         if let externalScreen = UIScreen.screens.last, externalScreen != UIScreen.main {
             let externalWindow = UIWindow(frame: externalScreen.bounds)
             externalWindow.screen = externalScreen
             let newExternalVC = ExternalDisplayViewController()
             newExternalVC.mainViewController = self
             externalWindow.rootViewController = newExternalVC
             externalWindow.isHidden = false
             externalVC = newExternalVC
         }
         */
    }
    
    // MARK: - Segmented Control
    private func setupTaskSegmentedControl() {
        segmentedControl.removeAllSegments()
        for (index, taskInfo) in tasks.enumerated() {
            segmentedControl.insertSegment(withTitle: taskInfo.name, at: index, animated: false)
        }
    }
    
    // MARK: - Load Local Models
    private func loadModelsForAllTasks() {
        for taskInfo in tasks {
            let taskName = taskInfo.name
            let folderName = taskInfo.folder
            let modelFiles = getModelFiles(in: folderName)
            modelsForTask[taskName] = modelFiles
        }
    }
    
    private func getModelFiles(in folderName: String) -> [String] {
        var result: [String] = []
        if let folderURL = Bundle.main.url(forResource: folderName, withExtension: nil) {
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(
                    at: folderURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                for fileURL in fileURLs {
                    if fileURL.pathExtension == "mlmodel" || fileURL.pathExtension == "mlpackage" {
                        let fileName = fileURL.lastPathComponent
                        result.append(fileName)
                    }
                }
            } catch {
                print("Error reading contents of folder \(folderName): \(error)")
            }
        }
        return result.sorted()
    }
    
    // MARK: - Reload Table
    private func reloadModelEntries(for taskName: String) {
        // build local entries
        let localFileNames = modelsForTask[taskName] ?? []
        let localEntries = localFileNames.map { fileName -> ModelEntry in
            let display = (fileName as NSString).deletingPathExtension
            return ModelEntry(
                displayName: display,
                identifier: fileName,
                isLocalBundle: true,
                isRemote: false,
                remoteURL: nil
            )
        }
        
        // build remote entries
        let remoteList = remoteModelsInfo[taskName] ?? []
        let remoteEntries = remoteList.map { (modelName, url) -> ModelEntry in
            ModelEntry(
                displayName: modelName,
                identifier: modelName,
                isLocalBundle: false,
                isRemote: true,
                remoteURL: url
            )
        }
        
        currentModels = localEntries + remoteEntries
        
        if !currentModels.isEmpty {
            modelTableView.isHidden = false
            modelTableView.reloadData()
            
            // By default, select the first row if you want
            DispatchQueue.main.async {
                let firstIndex = IndexPath(row: 0, section: 0)
                if self.currentModels.indices.contains(0) {
                    self.modelTableView.selectRow(at: firstIndex, animated: false, scrollPosition: .none)
                    self.selectedIndexPath = firstIndex
                }
            }
        } else {
            print("No models found for task: \(taskName)")
            modelTableView.isHidden = true
        }
    }

    // MARK: - IBAction
    @IBAction func vibrate(_ sender: Any) {
        selection.selectionChanged()
    }

    @IBAction func indexChanged(_ sender: UISegmentedControl) {
        selection.selectionChanged()
        
        let index = sender.selectedSegmentIndex
        guard tasks.indices.contains(index) else { return }
        
        let newTask = tasks[index].name
        
        // If no local or remote models, alert user
        if (modelsForTask[newTask]?.isEmpty ?? true) && (remoteModelsInfo[newTask]?.isEmpty ?? true) {
            let alert = UIAlertController(
                title: "\(newTask) Models not found",
                message: "Please add or define models for \(newTask).",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: { _ in
                alert.dismiss(animated: true)
            }))
            self.present(alert, animated: true)
            
            // revert the index to the old one
            if let oldIndex = tasks.firstIndex(where: { $0.name == currentTask }) {
                sender.selectedSegmentIndex = oldIndex
            }
            return
        }
        
        currentTask = newTask
        selectedIndexPath = nil
        
        // reload local/remote model entries for the new task
        reloadModelEntries(for: currentTask)
        
        // Optionally, you could also instruct the external VC to change tasks
        externalVC?.setCurrentTask(newTask)
    }
    
    @objc func logoButton() {
        selection.selectionChanged()
        if let link = URL(string: "https://www.ultralytics.com") {
            UIApplication.shared.open(link)
        }
    }
    
    // MARK: - TableView Setup
    private func setupTableView() {
        modelTableView.delegate = self
        modelTableView.dataSource = self
        modelTableView.register(UITableViewCell.self, forCellReuseIdentifier: "ModelCell")
        modelTableView.backgroundColor = .clear
        modelTableView.separatorStyle = .none
        modelTableView.isScrollEnabled = false
        
        tableViewBGView.backgroundColor = .darkGray.withAlphaComponent(0.3)
        tableViewBGView.layer.cornerRadius = 8
        tableViewBGView.clipsToBounds = true
        
        view.addSubview(tableViewBGView)
        view.addSubview(modelTableView)
        
        modelTableView.translatesAutoresizingMaskIntoConstraints = false
        tableViewBGView.frame = CGRect(
            x: modelTableView.frame.minX-1,
            y: modelTableView.frame.minY-1,
            width: modelTableView.frame.width+2,
            height: CGFloat(currentModels.count*30+2)
        )
    }
    
    // MARK: - Buttons
    private func setupButtons() {
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular, scale: .default)
        shareButton.setImage(UIImage(systemName: "square.and.arrow.up", withConfiguration: config), for: .normal)
        shareButton.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(shareButtonTapped)))
        view.addSubview(shareButton)
        
        recordButton.setImage(UIImage(systemName: "video", withConfiguration: config), for: .normal)
        recordButton.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(recordScreen)))
        view.addSubview(recordButton)

        logoImage.isUserInteractionEnabled = true
        logoImage.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(logoButton)))
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Layout for table (example logic)
        if view.bounds.width > view.bounds.height {
            shareButton.tintColor = .darkGray
            recordButton.tintColor = .darkGray
            let tableViewWidth = view.bounds.width * 0.2
            modelTableView.frame = CGRect(x: segmentedControl.frame.maxX + 20, y: 20, width: tableViewWidth, height: 200)
        } else {
            shareButton.tintColor = .systemGray
            recordButton.tintColor = .systemGray
            let tableViewWidth = view.bounds.width * 0.4
            modelTableView.frame = CGRect(
                x: view.bounds.width - tableViewWidth - 8,
                y: segmentedControl.frame.maxY + 25,
                width: tableViewWidth,
                height: 200
            )
        }
        
        shareButton.frame = CGRect(
            x: view.bounds.maxX - 49.5,
            y: view.bounds.maxY - 66,
            width: 49.5,
            height: 49.5
        )
        recordButton.frame = CGRect(
            x: shareButton.frame.minX - 49.5,
            y: view.bounds.maxY - 66,
            width: 49.5,
            height: 49.5
        )
        
        tableViewBGView.frame = CGRect(
            x: modelTableView.frame.minX-1,
            y: modelTableView.frame.minY-1,
            width: modelTableView.frame.width+2,
            height: CGFloat(currentModels.count*30+2)
        )
    }
    
    // MARK: - Share / Record
    @objc func shareButtonTapped() {
        selection.selectionChanged()
        // We need the external VC to capture the image from yoloView (which is there).
        externalVC?.capturePhoto { [weak self] captured in
            guard let self = self else { return }
            if let image = captured {
                DispatchQueue.main.async {
                    let activityVC = UIActivityViewController(
                        activityItems: [image],
                        applicationActivities: nil
                    )
                    activityVC.popoverPresentationController?.sourceView = self.View0
                    self.present(activityVC, animated: true, completion: nil)
                }
            } else {
                print("Error capturing photo from external VC’s yoloView")
            }
        }
    }
    
    @objc func recordScreen() {
        let recorder = RPScreenRecorder.shared()
        recorder.isMicrophoneEnabled = true
        
        if !recorder.isRecording {
            AudioServicesPlaySystemSound(1117)
            recordButton.tintColor = .red
            recorder.startRecording { error in
                if let error = error {
                    print("Screen recording start error: \(error)")
                } else {
                    print("Started screen recording.")
                }
            }
        } else {
            AudioServicesPlaySystemSound(1118)
            if view.bounds.width > view.bounds.height {
                recordButton.tintColor = .darkGray
            } else {
                recordButton.tintColor = .systemGray
            }
            recorder.stopRecording { [weak self] previewVC, error in
                if let error = error {
                    print("Stop recording error: \(error)")
                }
                if let previewVC = previewVC {
                    previewVC.previewControllerDelegate = self
                    self?.present(previewVC, animated: true, completion: nil)
                }
            }
        }
    }
}

// MARK: - RPPreviewViewControllerDelegate
extension MainViewController: RPPreviewViewControllerDelegate {
    func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
        previewController.dismiss(animated: true)
    }
}

// MARK: - UITableViewDataSource, UITableViewDelegate
extension MainViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return currentModels.count
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 30
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let cell = tableView.dequeueReusableCell(withIdentifier: "ModelCell", for: indexPath)
        let entry = currentModels[indexPath.row]
        
        cell.textLabel?.textAlignment = .center
        cell.textLabel?.text = entry.displayName
        cell.textLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        cell.backgroundColor = .clear
        
        // If it's remote, show a cloud-download icon if not yet downloaded
        if entry.isRemote {
            let isDownloaded = ModelCacheManager.shared.isModelDownloaded(key: entry.identifier)
            if !isDownloaded {
                cell.accessoryView = UIImageView(image: UIImage(systemName: "icloud.and.arrow.down"))
            } else {
                cell.accessoryView = nil
            }
        } else {
            cell.accessoryView = nil
        }
        
        let selectedBGView = UIView()
        selectedBGView.backgroundColor = UIColor(white: 1.0, alpha: 0.3)
        selectedBGView.layer.cornerRadius = 8
        selectedBGView.layer.masksToBounds = true
        cell.selectedBackgroundView = selectedBGView
        
        cell.selectionStyle = .default
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selection.selectionChanged()
        
        selectedIndexPath = indexPath
        let selectedEntry = currentModels[indexPath.row]
        
        // In the old code, you loaded the model in the same VC, but now
        // we simply instruct the external side:
        externalVC?.loadModel(entry: selectedEntry)
    }
    
    func tableView(_ tableView: UITableView,
                   willDisplay cell: UITableViewCell,
                   forRowAt indexPath: IndexPath) {
        if let selectedBGView = cell.selectedBackgroundView {
            let insetRect = cell.bounds.insetBy(dx: 4, dy: 4)
            selectedBGView.frame = insetRect
        }
    }
}


class ExternalDisplayViewController: UIViewController {
    
    // MARK: - Public reference back to the main VC (weak to avoid retain cycles)
    weak var mainViewController: MainViewController?
    
    @IBOutlet weak var yoloView: YOLOView!
    // MARK: - YOLO-Related UI (Programmatic)
    // No Storyboard outlets here, so it won’t get shrunk on large external screens
    
    
    // For demonstration, if you want an activity indicator on external as well,
    // you can create it programmatically. If you do NOT want it, remove these lines.
    // The main side also has an activityIndicator in the storyboard, but this is separate.
    private let externalActivityIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .large)
        ai.hidesWhenStopped = true
        return ai
    }()
    
    // If you want any progress view or label on the external side, define them here.
    private let downloadProgressView: UIProgressView = {
        let pv = UIProgressView(progressViewStyle: .default)
        pv.progress = 0.0
        pv.isHidden = true
        return pv
    }()
    
    private let downloadProgressLabel: UILabel = {
        let label = UILabel()
        label.text = ""
        label.textAlignment = .center
        label.textColor = .systemGray
        label.font = UIFont.systemFont(ofSize: 14)
        label.isHidden = true
        return label
    }()
    
    // MARK: - Overlay
    private var loadingOverlayView: UIView?
    
    // MARK: - Model Loading State
    private var isLoadingModel = false
    private var firstLoad = true
    private var currentTask: String = "Detect"
    private var currentModelName: String = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .black
        
        // 1. Add yoloView
        view.addSubview(yoloView)
        
        // 2. Activity indicator
        view.addSubview(externalActivityIndicator)
        
        // 3. Progress views
        view.addSubview(downloadProgressView)
        view.addSubview(downloadProgressLabel)
        
        // 4. Setup constraint or frames
        // (Below is a simple frames example for illustration; adapt as needed)
        let screenBounds = view.bounds
        yoloView.frame = screenBounds.insetBy(dx: 40, dy: 40)
        
        externalActivityIndicator.center = CGPoint(x: screenBounds.midX, y: screenBounds.midY)
        
        downloadProgressView.frame = CGRect(
            x: screenBounds.midX - 100,
            y: externalActivityIndicator.frame.maxY + 8,
            width: 200, height: 2
        )
        downloadProgressLabel.frame = CGRect(
            x: downloadProgressView.frame.minX,
            y: downloadProgressView.frame.maxY + 8,
            width: 200, height: 20
        )
        
        // 5. Setup optional progress handler from ModelDownloadManager
        ModelDownloadManager.shared.progressHandler = { [weak self] progress in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.downloadProgressView.progress = Float(progress)
                self.downloadProgressLabel.isHidden = false
                let percentage = Int(progress * 100)
                self.downloadProgressLabel.text = "Downloading \(percentage)%"
            }
        }
        
        // 6. If you want to do any initial camera setup automatically, do it here.
        //    Or wait until you load the first model.
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Re-adjust frames if the external screen changes size
        let screenBounds = view.bounds
        yoloView.frame = screenBounds.insetBy(dx: 40, dy: 40)
        externalActivityIndicator.center = CGPoint(x: screenBounds.midX, y: screenBounds.midY)
        downloadProgressView.frame = CGRect(
            x: screenBounds.midX - 100,
            y: externalActivityIndicator.frame.maxY + 8,
            width: 200, height: 2
        )
        downloadProgressLabel.frame = CGRect(
            x: downloadProgressView.frame.minX,
            y: downloadProgressView.frame.maxY + 8,
            width: 200, height: 20
        )
    }
    
    // MARK: - Public Methods Called by MainViewController
    
    /// e.g. when the user selects a new task in the iPhone UI
    func setCurrentTask(_ task: String) {
        currentTask = task
        print("External VC: setCurrentTask(\(task))")
    }
    
    /// e.g. when the user picks a model from the table in the iPhone UI
    func loadModel(entry: ModelEntry) {
        guard !isLoadingModel else {
            print("Model is already loading. Please wait.")
            return
        }
        isLoadingModel = true
        
        // Reset YOLO layers
        yoloView.resetLayers()
        
        // Show overlay if not first load
        if !firstLoad {
            showLoadingOverlay()
            yoloView.setInferenceFlag(ok: false)
        } else {
            firstLoad = false
        }
        
        externalActivityIndicator.startAnimating()
        downloadProgressView.progress = 0.0
        downloadProgressView.isHidden = true
        downloadProgressLabel.isHidden = true
        
        // Optionally also show activity indicator on main side:
        mainViewController?.activityIndicator.startAnimating()
        mainViewController?.view.isUserInteractionEnabled = false
        
        print("Start loading model: \(entry.displayName)")
        
        if entry.isLocalBundle {
            DispatchQueue.global().async { [weak self] in
                guard let self = self else { return }
                let yoloTask = self.convertTaskNameToYOLOTask(self.currentTask)
                
                 let folderURL = self.folderURL(forTask: self.currentTask)
                let modelURL = folderURL!.appendingPathComponent(entry.identifier)
//                else {
//                    DispatchQueue.main.async {
//                        self.finishLoadingModel(success: false, modelName: entry.displayName)
//                    }
//                    return
//                }
                
                DispatchQueue.main.async {
                    self.downloadProgressLabel.isHidden = false
                    self.downloadProgressLabel.text = "Loading \(entry.displayName)"
                    self.yoloView.setModel(modelPathOrName: modelURL.path, task: yoloTask) { result in
                        switch result {
                        case .success():
                            self.finishLoadingModel(success: true, modelName: entry.displayName)
                        case .failure(let error):
                            print(error)
                            self.finishLoadingModel(success: false, modelName: entry.displayName)
                        }
                    }
                }
            }
        } else {
            let yoloTask = convertTaskNameToYOLOTask(currentTask)
            let key = entry.identifier  // e.g. "yolov8n"
            
            if ModelCacheManager.shared.isModelDownloaded(key: key) {
                loadCachedModelAndSetToYOLOView(key: key, yoloTask: yoloTask, displayName: entry.displayName)
            } else {
                guard let remoteURL = entry.remoteURL else {
                    finishLoadingModel(success: false, modelName: entry.displayName)
                    return
                }
                
                downloadProgressView.progress = 0.0
                downloadProgressView.isHidden = false
                downloadProgressLabel.isHidden = false
                let localZipFileName = remoteURL.lastPathComponent
                
                ModelCacheManager.shared.loadModel(
                    from: localZipFileName,
                    remoteURL: remoteURL,
                    key: key
                ) { [weak self] mlModel, loadedKey in
                    guard let self = self else { return }
                    if mlModel == nil {
                        self.finishLoadingModel(success: false, modelName: entry.displayName)
                        return
                    }
                    self.loadCachedModelAndSetToYOLOView(key: loadedKey,
                                                         yoloTask: yoloTask,
                                                         displayName: entry.displayName)
                }
            }
        }
    }
    
    /// For the share button usage from MainViewController
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        yoloView.capturePhoto { capturedImage in
            completion(capturedImage)
        }
    }
    
    // MARK: - Private Helpers
    
    private func convertTaskNameToYOLOTask(_ task: String) -> YOLOTask {
        switch task {
        case "Detect":   return .detect
        case "Segment":  return .segment
        case "Classify": return .classify
        case "Pose":     return .pose
        case "Obb":      return .obb
        default:         return .detect
        }
    }
    
    private func folderURL(forTask task: String) -> URL? {
        // This corresponds to your tasks array from the main side
        // We replicate the logic for local folder name:
        let mapping: [String: String] = [
            "Classify": "ClassifyModels",
            "Segment":  "SegmentModels",
            "Detect":   "DetectModels",
            "Pose":     "PoseModels",
            "Obb":      "ObbModels"
        ]
        guard let folderName = mapping[task],
              let folderPathURL = Bundle.main.url(forResource: folderName, withExtension: nil)
        else {
            return nil
        }
        return folderPathURL
    }
    
    private func loadCachedModelAndSetToYOLOView(key: String,
                                                 yoloTask: YOLOTask,
                                                 displayName: String) {
        let localModelURL = ModelCacheManager.shared.getDocumentsDirectory()
            .appendingPathComponent(key)
            .appendingPathExtension("mlmodelc")
        
        DispatchQueue.main.async {
            self.downloadProgressLabel.isHidden = false
            self.downloadProgressLabel.text = "Loading \(displayName)"
            self.yoloView.setModel(modelPathOrName: localModelURL.path, task: yoloTask) { result in
                switch result {
                case .success():
                    self.finishLoadingModel(success: true, modelName: displayName)
                case .failure(let error):
                    print(error)
                    self.finishLoadingModel(success: false, modelName: displayName)
                }
            }
        }
    }
    
    private func showLoadingOverlay() {
        guard loadingOverlayView == nil else { return }
        let overlay = UIView(frame: view.bounds)
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.5)
                
        view.addSubview(overlay)
        loadingOverlayView = overlay
        view.bringSubviewToFront(downloadProgressView)
        view.bringSubviewToFront(downloadProgressLabel)

        view.isUserInteractionEnabled = false
    }
    
    private func hideLoadingOverlay() {
        loadingOverlayView?.removeFromSuperview()
        loadingOverlayView = nil
        view.isUserInteractionEnabled = true
    }
    
    private func finishLoadingModel(success: Bool, modelName: String) {
        DispatchQueue.main.async {
            self.externalActivityIndicator.stopAnimating()
            self.downloadProgressView.isHidden = true
            self.downloadProgressLabel.isHidden = true
            
            // Also stop main side’s activity indicator
            self.mainViewController?.activityIndicator.stopAnimating()
            self.mainViewController?.view.isUserInteractionEnabled = true
            
            self.isLoadingModel = false
            if !self.firstLoad {
                self.hideLoadingOverlay()
            }
            self.yoloView.setInferenceFlag(ok: true)

            if success {
                print("Finished loading model: \(modelName)")
                self.currentModelName = modelName
                self.downloadProgressLabel.text = "Finished loading model \(modelName)"
                self.downloadProgressLabel.isHidden = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.downloadProgressLabel.isHidden = true
                    self.downloadProgressLabel.text = ""
                }
                
            } else {
                print("Failed to load model: \(modelName)")
            }
        }
    }
}
