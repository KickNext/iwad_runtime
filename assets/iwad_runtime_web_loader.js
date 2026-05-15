(function () {
  const persistencePath = "/iwad-runtime-data";
  const modules = new Map();
  const scripts = new Map();

  function loadScript(url) {
    if (scripts.has(url)) {
      return scripts.get(url);
    }

    const promise = new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.src = url;
      script.async = true;
      script.onload = resolve;
      script.onerror = () => reject(new Error(`Failed to load ${url}`));
      document.head.appendChild(script);
    });
    scripts.set(url, promise);
    return promise;
  }

  window.iwadRuntimeCreate = async function iwadRuntimeCreate(scriptUrl, wasmUrl) {
    const key = `${scriptUrl}|${wasmUrl}`;
    if (modules.has(key)) {
      return modules.get(key);
    }

    await loadScript(scriptUrl);
    const factory = window.createIwadrModule;
    if (typeof factory !== "function") {
      throw new Error("createIwadrModule was not exported by iwad_runtime_web.js");
    }

    const module = await factory({
      locateFile(path) {
        return path.endsWith(".wasm") ? wasmUrl : path;
      },
      noInitialRun: true,
      print: console.log,
      printErr: console.warn,
    });

    let syncInFlight = null;
    let syncAgain = false;

    function syncFs(populate) {
      return new Promise((resolve, reject) => {
        module.FS.syncfs(populate, (error) => {
          if (error) {
            reject(error);
          } else {
            resolve();
          }
        });
      });
    }

    async function flushPersistence() {
      if (syncInFlight !== null) {
        syncAgain = true;
        return syncInFlight;
      }

      syncInFlight = syncFs(false)
        .catch((error) => console.warn("iwad_runtime persistence sync failed", error))
        .finally(async () => {
          syncInFlight = null;
          if (syncAgain) {
            syncAgain = false;
            await flushPersistence();
          }
        });
      return syncInFlight;
    }

    if (module.FS.filesystems && module.FS.filesystems.IDBFS) {
      try {
        module.FS.mkdir(persistencePath);
      } catch (error) {
        // Directory already exists in MEMFS.
      }
      module.FS.mount(module.FS.filesystems.IDBFS, {}, persistencePath);
      await syncFs(true);
      module.ccall("iwadr_set_temp_dir", null, ["string"], [persistencePath]);
    } else {
      console.warn("iwad_runtime_web.js was built without IDBFS persistence");
    }

    function heapU8() {
      if (module.HEAPU8 instanceof Uint8Array) {
        return module.HEAPU8;
      }
      throw new Error("iwad_runtime_web.js did not export HEAPU8");
    }

    const api = {
      get isStarted() {
        return module._iwadr_is_started() !== 0;
      },
      get hasQuit() {
        return typeof module._iwadr_has_quit === "function"
          ? module._iwadr_has_quit() !== 0
          : false;
      },
      get lastError() {
        const pointer = module._iwadr_last_error();
        return pointer ? module.UTF8ToString(pointer) : "";
      },
      get currentWeaponSlot() {
        return module._iwadr_current_weapon_slot();
      },
      get ownedWeaponSlotsMask() {
        return module._iwadr_owned_weapon_slots_mask();
      },
      get isGameplayActive() {
        return module._iwadr_is_gameplay_active() !== 0;
      },
      get isPlayerDead() {
        return typeof module._iwadr_is_player_dead === "function"
          ? module._iwadr_is_player_dead() !== 0
          : false;
      },
      get isAdvanceActive() {
        return typeof module._iwadr_is_advance_active === "function"
          ? module._iwadr_is_advance_active() !== 0
          : false;
      },
      get isMenuActive() {
        return module._iwadr_is_menu_active() !== 0;
      },
      get isMenuPromptActive() {
        return typeof module._iwadr_is_menu_prompt_active === "function"
          ? module._iwadr_is_menu_prompt_active() !== 0
          : module._iwadr_is_quit_confirm_active() !== 0;
      },
      get isSaveNameActive() {
        return typeof module._iwadr_is_save_name_active === "function"
          ? module._iwadr_is_save_name_active() !== 0
          : false;
      },
      get isQuitConfirmActive() {
        return module._iwadr_is_quit_confirm_active() !== 0;
      },
      startBytes(bytes, fileName) {
        const wadName = fileName || "game.wad";
        module.FS.writeFile(`/${wadName}`, bytes);
        return module.ccall("iwadr_start", "number", ["string"], [`/${wadName}`]);
      },
      startNewGame(skill, episode, map) {
        return module._iwadr_start_new_game(skill, episode, map);
      },
      async saveGame(slot, description) {
        const result = module.ccall(
          "iwadr_save_game",
          "number",
          ["number", "string"],
          [slot, description || "IWAD Runtime"],
        );
        await flushPersistence();
        return result;
      },
      async loadGame(slot) {
        await syncFs(true);
        return module._iwadr_load_game(slot);
      },
      saveGameExists(slot) {
        return module._iwadr_save_game_exists(slot) !== 0;
      },
      saveGameSize(slot) {
        return module._iwadr_save_game_size(slot);
      },
      get saveGeneration() {
        return module._iwadr_save_generation();
      },
      flushPersistence,
      tick() {
        const generationBefore = module._iwadr_save_generation();
        const result = module._iwadr_tick();
        if (module._iwadr_save_generation() !== generationBefore) {
          void flushPersistence();
        }
        return result;
      },
      copyFrame(out) {
        const pointer = module._malloc(out.length);
        try {
          const copied = module._iwadr_copy_frame_rgba(pointer, out.length);
          if (copied > 0) {
            out.set(heapU8().subarray(pointer, pointer + copied));
          }
          return copied;
        } finally {
          module._free(pointer);
        }
      },
      copyFrameBytes(length) {
        const out = new Uint8Array(length);
        const pointer = module._malloc(length);
        try {
          const copied = module._iwadr_copy_frame_rgba(pointer, length);
          if (copied > 0) {
            out.set(heapU8().subarray(pointer, pointer + copied));
            return out.subarray(0, copied);
          }
          return new Uint8Array(0);
        } finally {
          module._free(pointer);
        }
      },
      keyEvent(inputKey, pressed) {
        module._iwadr_key_event(inputKey, pressed);
      },
      requestWeaponSlot(slot) {
        module._iwadr_request_weapon_slot(slot);
      },
      mouseEvent(buttons, deltaX, deltaY) {
        module._iwadr_mouse_event(buttons, deltaX, deltaY);
      },
      setSuspended(suspended) {
        if (typeof module._iwadr_set_suspended === "function") {
          module._iwadr_set_suspended(suspended);
        }
      },
      shutdown() {
        if (typeof module._iwadr_shutdown === "function") {
          module._iwadr_shutdown();
        } else if (typeof module._iwadr_set_suspended === "function") {
          module._iwadr_set_suspended(1);
        }
        void flushPersistence();
      },
    };

    modules.set(key, api);
    return api;
  };
})();
