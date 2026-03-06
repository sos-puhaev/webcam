import SwiftUI

enum GridLayoutType: String, CaseIterable {
    case twoByTwo = "2x2"
    case threeByTwo = "3x2"
    case threeByThree = "3x3"
    
    var columns: Int {
        switch self {
        case .twoByTwo: return 2
        case .threeByTwo: return 3
        case .threeByThree: return 3
        }
    }
    
    var aspectRatio: CGFloat {
        switch self {
        case .twoByTwo: return 4/3
        case .threeByTwo: return 3/2
        case .threeByThree: return 1
        }
    }
    
    var icon: String {
        switch self {
        case .twoByTwo: return "square.grid.2x2"
        case .threeByTwo: return "rectangle.grid.3x2"
        case .threeByThree: return "square.grid.3x3"
        }
    }
}

struct CameraListView: View {
    @StateObject private var viewModel = CameraListViewModel()
    @State private var gridLayout: GridLayoutType = .twoByTwo
    @State private var selectedCamera: Camera?
    @State private var showCameraDetail = false
    @State private var showAddCamera = false
    @State private var refreshToken = UUID()

    
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: gridLayout.columns)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                gridControlPanel
                cameraContent
            }
            .navigationTitle("Камеры")
            .onAppear {
                refreshToken = UUID()
                
                if viewModel.cameras.isEmpty {
                    viewModel.loadCameras()
                }
            }
            .background(
                NavigationLink(
                    destination: Group {
                        if let camera = selectedCamera {
                            CameraDetailView(
                                camera: camera,
                                viewModel: viewModel
                            )
                        }
                    },
                    isActive: $showCameraDetail,
                    label: { EmptyView() }
                )
            )
            .sheet(isPresented: $showAddCamera) {
                AddCameraView()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddCamera = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .shadow(color: .blue.opacity(0.3), radius: 3)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // остальная часть файла у тебя ок (gridControlPanel / cameraContent / camerasGridView)
    // (оставь твою реализацию с prefetchIds как есть)
    
    private var gridControlPanel: some View {
        HStack {
            Text("Расположение:")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            HStack(spacing: 12) {
                ForEach(GridLayoutType.allCases, id: \.self) { layout in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            gridLayout = layout
                        }
                    } label: {
                        Image(systemName: layout.icon)
                            .font(.system(size: 18))
                            .foregroundColor(gridLayout == layout ? .blue : .gray)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(gridLayout == layout ? Color.blue.opacity(0.1) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.gray.opacity(0.2)),
            alignment: .bottom
        )
    }
    
    private var cameraContent: some View {
        Group {
            if viewModel.isLoading && viewModel.cameras.isEmpty {
                VStack {
                    Spacer()
                    ProgressView().scaleEffect(1.2)
                    Text("Загрузка камер...")
                        .foregroundColor(.secondary)
                        .padding(.top, 12)
                    Spacer()
                }
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    Text("Ошибка загрузки").font(.headline)
                    Text(error)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Повторить") { viewModel.loadCameras() }
                        .buttonStyle(.bordered)
                        .padding(.top, 8)
                    Spacer()
                }
                .padding()
            } else if viewModel.cameras.isEmpty {
                VStack(spacing: 24) {
                    Spacer()
                    Image(systemName: "video.slash")
                        .font(.system(size: 60))
                        .foregroundColor(.gray.opacity(0.5))
                    VStack(spacing: 8) {
                        Text("Нет камер")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Добавьте первую камеру")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Button {
                        showAddCamera = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Добавить камеру").fontWeight(.medium)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .padding(.top, 16)
                    Spacer()
                }
                .padding()
            } else {
                camerasGridView
            }
        }
    }

    private var camerasGridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(viewModel.cameras.indices, id: \.self) { index in
                    let cams = viewModel.cameras
                    let camera = cams[index]

                    let radius = max(2, gridLayout.columns * 2)
                    let start = max(0, index - radius)
                    let end = min(cams.count - 1, index + radius)
                    let prefetchIds = cams[start...end]
                        .map { $0.id }
                        .filter { $0 != camera.id }

                    CameraRowView(
                        camera: camera,
                        viewModel: viewModel,
                        gridLayout: gridLayout,
                        prefetchCameraIds: prefetchIds
                    )
                    .aspectRatio(gridLayout.aspectRatio, contentMode: .fit)
                    .onTapGesture {
                        selectedCamera = camera
                        CameraStreamPrefetch.shared.prefetchLive(cameraId: camera.id)
                        showCameraDetail = true
                    }
                }
            }
            .padding(12)
        }
        .id(refreshToken)
    }
}
