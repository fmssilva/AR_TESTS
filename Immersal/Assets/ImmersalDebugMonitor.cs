using System.Collections;
using UnityEngine;
using Immersal;
using Immersal.XR;

/// <summary>
/// Attach to any active GameObject. Logs Immersal localization events using
/// Debug.LogError so they appear in the filtered _error_logs.txt on device.
/// Remove or disable before shipping.
/// </summary>
public class ImmersalDebugMonitor : MonoBehaviour
{
    [Tooltip("How often (seconds) to log the current localization state.")]
    public float reportInterval = 3f;

    private IEnumerator Start()
    {
        Debug.LogError("[ImmersalDebug] Monitor started. Waiting for ImmersalSDK instance...");

        // Wait until ImmersalSDK is available
        float timeout = 10f;
        float elapsed = 0f;
        while (ImmersalSDK.Instance == null && elapsed < timeout)
        {
            yield return new WaitForSeconds(0.5f);
            elapsed += 0.5f;
        }

        if (ImmersalSDK.Instance == null)
        {
            Debug.LogError("[ImmersalDebug] ImmersalSDK.Instance is NULL after 10s. SDK not initialised.");
            yield break;
        }

        Debug.LogError($"[ImmersalDebug] ImmersalSDK found. Token set: {!string.IsNullOrWhiteSpace(ImmersalSDK.Instance.developerToken)}");

        // Find the XRMap in the scene
        XRMap[] maps = FindObjectsByType<XRMap>(FindObjectsSortMode.None);
        Debug.LogError($"[ImmersalDebug] XRMap count in scene: {maps.Length}");
        foreach (var m in maps)
        {
            Debug.LogError($"[ImmersalDebug] Map: id={m.mapId} name={m.mapName} configured={m.IsConfigured} mapFile={(m.mapFile != null ? m.mapFile.name : "NULL")} locMethod={(m.LocalizationMethod != null ? m.LocalizationMethod.GetType().Name : "NULL")}");
        }

        // Hook into MapManager registered event
        MapManager.MapRegisteredAndLoaded?.AddListener(OnMapRegistered);

        // Find Localizer
        Localizer localizer = FindFirstObjectByType<Localizer>();
        if (localizer == null)
        {
            Debug.LogError("[ImmersalDebug] Localizer component NOT FOUND in scene.");
        }
        else
        {
            Debug.LogError($"[ImmersalDebug] Localizer found: enabled={localizer.enabled} isActiveAndEnabled={localizer.isActiveAndEnabled}");
        }

        // Periodic state reports
        while (true)
        {
            yield return new WaitForSeconds(reportInterval);
            ReportState(localizer);
        }
    }

    private void OnMapRegistered(int mapId)
    {
        Debug.LogError($"[ImmersalDebug] MAP REGISTERED & LOADED: id={mapId}");
    }

    private void ReportState(Localizer localizer)
    {
        string locState = localizer != null
            ? $"enabled={localizer.enabled} active={localizer.isActiveAndEnabled}"
            : "NULL";

        XRMap[] maps = FindObjectsByType<XRMap>(FindObjectsSortMode.None);
        string mapPos = maps.Length > 0
            ? maps[0].transform.position.ToString("F3")
            : "no maps";

        Debug.LogError($"[ImmersalDebug] State @ {Time.time:F1}s — Localizer: {locState} | XRMap[0] worldPos: {mapPos}");
    }

    private void OnDestroy()
    {
        MapManager.MapRegisteredAndLoaded?.RemoveListener(OnMapRegistered);
    }
}
