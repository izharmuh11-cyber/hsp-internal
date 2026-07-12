// PhotoStore.swift
// HaispaceBooths — Core/State
//
// Store untuk semua foto dalam sesi yang sedang aktif.
// Mengelola dual-channel receipt (thumbnail cepat + full quality background).
//
// Ref: docs/design/39_state_architecture.md — PhotoStore
// Ref: docs/design/40_concurrency_strategy.md — AIC Dual-Channel

import Foundation
import Observation

// MARK: - PhotoStore

@Observable
final class PhotoStore {

    // MARK: State

    /// Semua foto yang masuk dari iPhone via P2P — terurut berdasarkan sortOrder
    private(set) var capturedPhotos: [CapturedPhoto] = []

    /// ID foto yang dipilih tamu (subset dari capturedPhotos)
    var selectedPhotoIds: Set<String> = []

    /// Foto final setelah dikomposit dengan frame + filter
    var finalPhotos: [RenderedPhoto] = []

    // Frame dan filter yang dipilih tamu
    var selectedFrameId: String?
    var selectedFilterName: String?

    // MARK: Computed

    /// Foto yang dipilih tamu (sorted by sortOrder)
    var selectedPhotos: [CapturedPhoto] {
        capturedPhotos
            .filter { selectedPhotoIds.contains($0.id) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Total foto yang sudah diterima
    var capturedCount: Int { capturedPhotos.count }

    /// Apakah semua foto sudah full quality?
    var allPhotosFullQuality: Bool {
        !capturedPhotos.isEmpty && capturedPhotos.allSatisfy { $0.isFullQuality }
    }

    /// Apakah ada foto yang masih thumbnail (transfer belum selesai)?
    var hasPendingTransfers: Bool {
        capturedPhotos.contains { !$0.isFullQuality }
    }

    // MARK: - Receive from P2P (Channel 1 — Thumbnail)

    /// Dipanggil saat thumbnail tiba dari iPhone (Channel 1 — cepat, <100ms)
    @MainActor
    func receiveThumbnail(_ thumbnail: PhotoThumbnail) {
        // Hindari duplikat
        guard !capturedPhotos.contains(where: { $0.id == thumbnail.photoId }) else {
            HaispaceLogger.debug("Thumbnail duplikat diabaikan: \(thumbnail.photoId)")
            return
        }

        let photo = CapturedPhoto(
            id: thumbnail.photoId,
            thumbnailData: thumbnail.data,
            capturedAt: thumbnail.capturedAt,
            sortOrder: thumbnail.sortOrder
        )
        capturedPhotos.append(photo)
        capturedPhotos.sort { $0.sortOrder < $1.sortOrder }

        HaispaceLogger.info("Thumbnail diterima — foto ke-\(thumbnail.sortOrder + 1)", category: "photo")
    }

    // MARK: - Upgrade to Full Quality (Channel 2)

    /// Dipanggil saat full quality tiba dari iPhone (Channel 2 — background)
    @MainActor
    func upgradeToFullQuality(photoId: String, fullData: Data) {
        guard let photo = capturedPhotos.first(where: { $0.id == photoId }) else {
            HaispaceLogger.warning("upgradeToFullQuality: foto tidak ditemukan — \(photoId)", category: "photo")
            return
        }
        photo.upgradeToFull(data: fullData)
        HaispaceLogger.info("Full quality diterima untuk foto: \(photoId)", category: "photo")
    }

    // MARK: - Selection Management

    /// Toggle pilihan foto (dengan batas maksimal)
    func toggleSelection(photoId: String, limit: Int) {
        if selectedPhotoIds.contains(photoId) {
            selectedPhotoIds.remove(photoId)
        } else if selectedPhotoIds.count < limit {
            selectedPhotoIds.insert(photoId)
        }
        // Jika sudah di limit — tidak melakukan apa-apa (bukan error)
    }

    /// Pilih semua foto (digunakan saat paket "all photos")
    func selectAll(limit: Int) {
        let idsToSelect = capturedPhotos.prefix(limit).map { $0.id }
        selectedPhotoIds = Set(idsToSelect)
    }

    /// Batalkan semua pilihan
    func clearSelection() {
        selectedPhotoIds.removeAll()
    }

    // MARK: - Reset

    /// Reset semua foto (saat sesi selesai atau di-reset operator)
    @MainActor
    func reset() {
        capturedPhotos.removeAll()
        selectedPhotoIds.removeAll()
        finalPhotos.removeAll()
        selectedFrameId = nil
        selectedFilterName = nil
        HaispaceLogger.info("PhotoStore di-reset", category: "photo")
    }

    // MARK: - Previews Helper

    func addPhotoForPreview(_ photo: CapturedPhoto) {
        capturedPhotos.append(photo)
    }
}
