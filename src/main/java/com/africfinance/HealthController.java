package com.africfinance;

import java.util.Map;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/** Expose le point d'accès HTTP minimal de l'application. */
@RestController
public class HealthController {

    @GetMapping("/")
    public Map<String, String> home() {
        return Map.of(
                "message", "Hello AfricFinance",
                "status", "running"
        );
    }
}
