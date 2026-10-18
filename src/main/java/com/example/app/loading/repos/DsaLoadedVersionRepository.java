package com.example.app.loading.repos;

import org.springframework.data.jpa.repository.JpaRepository;

import com.example.app.loading.models.DsaLoadedVersion;

public interface DsaLoadedVersionRepository extends JpaRepository<DsaLoadedVersion, Long> {}
