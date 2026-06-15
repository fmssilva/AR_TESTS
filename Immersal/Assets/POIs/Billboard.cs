using UnityEngine;

public class LookAtCamera : MonoBehaviour
{
    private Transform mainCameraTransform;

    void Start()
    {
        // Cache the main AR camera transform for performance
        if (Camera.main != null)
        {
            mainCameraTransform = Camera.main.transform;
        }
    }

    void LateUpdate()
    {
        if (mainCameraTransform != null)
        {
            // Point the text container directly at the camera
            transform.LookAt(transform.position + mainCameraTransform.rotation * Vector3.forward,
                             mainCameraTransform.rotation * Vector3.up);
        }
    }
}