package com.example.app.repos;

import org.springframework.data.jpa.repository.JpaRepository;

import com.example.app.models.DsaLoadedVersion;

public interface DsaLoadedVersionRepository extends JpaRepository<DsaLoadedVersion, Long> {}
