package com.example.app.dictionary.repos;

import org.springframework.data.jpa.repository.JpaRepository;

import com.example.app.dictionary.model.DirectionType;

public interface DirectionTypeRepository extends JpaRepository<DirectionType, Long> {}
