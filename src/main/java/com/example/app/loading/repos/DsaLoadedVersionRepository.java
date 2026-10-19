package com.example.app.loading.repos;

import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

import com.example.app.loading.models.DsaLoadedVersion;

public interface DsaLoadedVersionRepository extends JpaRepository<DsaLoadedVersion, Long> {

    Optional<DsaLoadedVersion> findByEntityName(String entityName);

}
