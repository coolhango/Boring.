// Copyright © 2024 Gedeon Koh All rights reserved.
// No part of this publication may be reproduced, distributed, or transmitted in any form or by any means, including photocopying, recording, or other electronic or mechanical methods, without the prior written permission of the publisher, except in the case of brief quotations embodied in reviews and certain other non-commercial uses permitted by copyright law.
// THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT. IN NO EVENT SHALL THE AUTHOR OR COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
// Use of this program for pranks or any malicious activities is strictly prohibited. Any unauthorized use or dissemination of the results produced by this program is unethical and may result in legal consequences.
// This code has been tested throughly. Please inform the operator or author if there is any mistake or error in the code.
// Any damage, disciplinary actions or death from this material is not the publisher's or owner's fault.
// Run and use this program this AT YOUR OWN RISK.
// Version 0.1

// This Space is for you to experiment your codes
// Start Typing Below :) ↓↓↓

import SwiftUI
import Combine
import AppKit

var defaultImage: NSImage = NSImage(
    systemSymbolName: "moon.fill",
    accessibilityDescription: "Album Art"
)!

class MusicManager: ObservableObject {
    private var cancellables = Set<AnyCancellable>()
    private var debounceToggle: DispatchWorkItem?
    private var musicSneakPeakDispatch: DispatchWorkItem?
    private var vm: BoringViewModel
    @Published var songTitle: String = "I'm Handsome"
    @Published var artistName: String = "Cool Hango"
    @Published var albumArt: NSImage = defaultImage
    var albumArtData: Data?
    @Published var isPlaying = false
    @Published var musicToggledManually: Bool = false
    @Published var album: String = "Self Love"
    @Published var playbackManager = PlaybackManager()
    @Published var lastUpdated: Date = Date()
    @Published var isPlayerIdle: Bool = true
    @Published var animations: BoringAnimations = BoringAnimations()
    @Published var avgColor: NSColor = .white
    
    private let mediaRemoteBundle: CFBundle
    private let MRMediaRemoteGetNowPlayingInfo: @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private let MRMediaRemoteRegisterForNowPlayingNotifications: @convention(c) (DispatchQueue) -> Void
    
    init?(vm: BoringViewModel) {
        self.vm = vm
        
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")) else {
            print("Failed to load MediaRemote.framework")
            return nil
        }
        self.mediaRemoteBundle = bundle
        
        guard let MRMediaRemoteGetNowPlayingInfoPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString),
              let MRMediaRemoteRegisterForNowPlayingNotificationsPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteRegisterForNowPlayingNotifications" as CFString) else {
            print("Failed to get function pointers")
            return nil
        }
        
        self.MRMediaRemoteGetNowPlayingInfo = unsafeBitCast(MRMediaRemoteGetNowPlayingInfoPointer, to: (@convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void).self)
        self.MRMediaRemoteRegisterForNowPlayingNotifications = unsafeBitCast(MRMediaRemoteRegisterForNowPlayingNotificationsPointer, to: (@convention(c) (DispatchQueue) -> Void).self)
        
        setupNowPlayingObserver()
        fetchNowPlayingInfo()
    }
    
    deinit {
        debounceToggle?.cancel()
        cancellables.removeAll()
    }
    
    private func setupNowPlayingObserver() {
        MRMediaRemoteRegisterForNowPlayingNotifications(DispatchQueue.main)
        
        NotificationCenter.default.publisher(for: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"))
            .sink { [weak self] _ in
                self?.fetchNowPlayingInfo()
            }
            .store(in: &cancellables)
        
            // Keep existing observers for Spotify and Apple Music
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.fetchNowPlayingInfo()
        }
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.fetchNowPlayingInfo()
        }
    }
    
    @objc func fetchNowPlayingInfo(bypass: Bool = false) {
        if musicToggledManually && !bypass {
            return
        }
        
        MRMediaRemoteGetNowPlayingInfo(DispatchQueue.main) { [weak self] information in
            guard let self = self else { self?.isPlaying = false; return }
            
            if let state = information["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Int {
                if !self.isPlaying && state == 0 {
                    return
                }
                self.musicIsPaused(state: state == 1, setIdle: true)
            } else if self.isPlaying {
                self.musicIsPaused(state: false, setIdle: true)
            }
            
            let albumArtData: Data? = information["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
            
            if albumArtData == nil {
                return
            }
            
            if let artist = information["kMRMediaRemoteNowPlayingInfoArtist"] as? String {
                self.artistName = artist
            }
            
            if let title = information["kMRMediaRemoteNowPlayingInfoTitle"] as? String {
                self.songTitle = title
            }
            
            if let album = information["kMRMediaRemoteNowPlayingInfoAlbum"] as? String {
                self.album = album
            }
            
            if let title = information["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
               title == self.songTitle && albumArtData == nil {
                return
            } else if albumArtData == self.albumArtData {
                return
            }
            
            if let albumArtData = albumArtData,
               let artworkImage = NSImage(data: albumArtData) {
                self.albumArtData = albumArtData
                self.updateAlbumArt(newAlbumArt: artworkImage)
            }
        }
    }
    
    func musicIsPaused(state: Bool, bypass: Bool = false, setIdle: Bool = false) {
        if self.musicToggledManually && !bypass {
            return
        }
        
        withAnimation {
            self.isPlaying = state
            self.playbackManager.isPlaying = state
            
            if !state {
                self.lastUpdated = Date()
            }
            
            if self.isPlaying && self.albumArtData != nil {
                self.vm.toggleSneakPeak(status: true, type: SneakContentType.music)
            }
            
            if setIdle && state {
                self.isPlayerIdle = false
                debounceToggle?.cancel()
                print("Setting not idle")
            } else if setIdle && !state {
                debounceToggle = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    if self.lastUpdated.timeIntervalSinceNow < -self.vm.waitInterval {
                        withAnimation {
                            self.isPlayerIdle = !self.isPlaying
                        }
                    }
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + self.vm.waitInterval, execute: debounceToggle!)
            }
        }
    }
    
    func togglePlayPause() {
        musicToggledManually = true
        
        let playState: Bool = playbackManager.playPause()
        
        musicIsPaused(state: playState, bypass: true, setIdle: true)
        
        if playState {
            fetchNowPlayingInfo(bypass: true)
        } else {
            lastUpdated = Date()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.musicToggledManually = false
        }
    }
    
    func updateAlbumArt(newAlbumArt: NSImage) {
        withAnimation(vm.animation) {
            self.albumArt = newAlbumArt
            if vm.coloredSpectrogram {
                calculateAverageColor()
            }
        }
    }
    
    func calculateAverageColor() {
        albumArt.averageColor { [weak self] color in
            DispatchQueue.main.async {
                self?.avgColor = color!
            }
        }
    }
    
    func nextTrack() {
        playbackManager.nextTrack()
        fetchNowPlayingInfo(bypass: true)
    }
    
    func previousTrack() {
        playbackManager.previousTrack()
        fetchNowPlayingInfo(bypass: true)
    }
}
